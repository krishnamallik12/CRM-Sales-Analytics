# CRM Sales & Pipeline Diagnostic
> **95% of the active pipeline - $4.59M out of $4.82M is stale or at risk of being lost. The sales team is spending 30+ days on 45% of deals that will never close. This project diagnoses exactly where the revenue is leaking and why.**
(Figures reflect the default 2017 view)

**Tech Stack:** MySQL · Power BI · Power Query · DAX

## The Problem
 
A B2B technology company's sales organization had no real visibility into pipeline health. Deals were silently dying, revenue was at risk, and gut feeling was filling the gap where data should have been.
 
This project was built to answer the questions a sales director actually loses sleep over:
 
- Where is active pipeline dying and how much is it worth?
- Are we losing deals because of bad leads, or because we can't close?
- Which accounts and products are worth our sales effort?
**Dataset:** 8,800 sales opportunities across 4 tables, covering October 2016–December 2017 across three regional offices.
 
---
 
## Key Findings
 
| Finding | Detail |
|---|---|
| 🔴 **$4.59M pipeline at risk** | 95% of active pipeline is stale (>90 days open) or stuck in prospecting |
| ⏳ **Closing problem, not a lead problem** | Only 11% of lost deals were instant rejections - 45% dragged on 30+ days before going cold |
| ⚡ **Top agent defies the tradeoff** | Darcel Schlecht generated $1.15M - more than double the next agent - while closing 2 days *faster* than average |
 
---

## Project Architecture
 
```
Raw CRM Data (CSV)
    ↓
MySQL - Staging tables, cleaning, 8 analytical queries
    ↓
Power BI - Star schema data model, Power Query transformations
    ↓
4-page Dashboard - Executive, Pipeline Risk, Product, Account views
```

---


## Part 1: SQL Data Cleaning & Analysis (MySQL)

### Approach
 
Before any cleaning, I created staging copies of every table. All transformations happened on staging only - the original data was never touched. This matters in a real environment where raw data needs to be auditable.

### What Was Cleaned
 
**Date standardization** - `engage_date` and `close_date` had mixed formats across rows. Detected every format variation and standardized to a clean `DATE` datatype using `STR_TO_DATE()` with multiple format patterns.
 
**Close value logic** - Applied a defensive `UPDATE` using `LEFT JOIN` to the Products table to enforce consistent `close_value` across all deal stages: won deals fall back to `sales_price` if missing; lost deals explicitly set to 0; open deals left as NULL (no revenue assumed).
 
**NULL account investigation** - 1,425 records (16.2% of the dataset) had no linked account. Rather than deleting them, I investigated why. Every single NULL account record was in either Prospecting or Engaging stage - never Won or Lost. This is normal CRM behavior: early-stage leads that haven't been formally linked to an account yet. Flagged with a `has_account` column and kept in the dataset.
 
**Sector typo** - Found and corrected "technolgy" → "technology" across all affected rows.
 
### A Structural Discovery in the Data
 
Every lost deal had both an `engage_date` and a `close_date` - meaning the sales team made contact before the deal was marked lost. This exposed something important: leads that were contacted but never responded were **not** being marked as lost. They were sitting in Prospecting indefinitely, inflating the pipeline with dead weight that reads as active opportunity.
 
---


## SQL Business Analysis (8 Questions)

**Q1 - Quarter-over-Quarter Revenue by Product**
Used `LAG()` window function to compare each product's revenue against the prior quarter. Finding: Nearly every product saw a sharp revenue spike in Q2 (GTK 500 up 621%, GTX Pro up 186%), followed by contraction through Q3 and Q4.
 
**Q2 - Agent-Level Efficiency**
Finding: High revenue does not require a longer sales cycle. Darcel Schlecht generated $1.15M (more than double the next agent) while closing in 49.4 days - 2 days faster than the company average. This is not a volume story; it is an efficiency story.
 
**Q3 - Sector Performance**
 
```sql
select 
    a.sector,
    sum(case when sp.deal_stage = 'won' then sp.close_value else 0 end) as closed_won_revenue,
    count(case when sp.deal_stage = 'won' then 1 end) as won_deals,
    round(count(case when sp.deal_stage = 'won' then 1 end)/nullif(count(case when sp.deal_stage in ('won','lost') then 1 end),0) * 100,2) as win_rate_percentage,
    round(sum(case when sp.deal_stage = 'won' then sp.close_value else 0 end)/nullif(count(case when sp.deal_stage = 'won' then 1 end),0),2) as avg_won_deal_value
from sales_pipeline_staging sp
inner join accounts_staging a on sp.account = a.account
where sp.account is not null
group by a.sector
order by closed_won_revenue desc;
```
 
Finding: Retail leads all sectors in raw revenue ($1.87M), but it isn't the strongest performer on any efficiency metric. Marketing converts best (64.85% win rate) and Entertainment closes the largest average deals ($2,650), despite ranking near the bottom on total revenue. Win rates are tightly clustered across sectors (61–65%), so revenue differences are driven mainly by deal volume, not conversion skill.
 
**Q4 -Account Efficiency Analysis**
Finding: Kan-code drives the most total revenue ($341K) but converts at only 61.50% which is one of the lower win rates among top accounts. Rangreen (75.00%) and Goodsilron (73.86%) convert far more efficiently despite generating less than half the revenue. Total volume and win-rate efficiency are two different stories. Hence, a large revenue number doesn't necessarily mean the account is easy to close.
 
**Q5 - How Long Does It Take for a Lost Deal to Drop Off?**
 
```sql
with categorized_loss as(
	select opportunity_id,
    case
		when datediff(close_date,engage_date)<=2 then 'Early Drop-off (0-2 Days)'
        when datediff(close_date,engage_date) between 3 and 30 then 'Short Sales Cycle (3-30 Days)'
        else 'Long Sales Cycle (31+ Days)'
	end as drop_off_category
    from sales_pipeline_staging
    where deal_stage = 'lost'
    and close_date is not null
    and engage_date is not null)
select drop_off_category, count(*) as Total_lost_deals,
round((count(*)/sum(count(*)) over())*100,2) as Lost_Percent
from categorized_loss 
group by drop_off_category
order by 
case drop_off_category
    when 'Early Drop-off (0-2 Days)' then 1
    when 'Short Sales Cycle (3-30 Days)' then 2
    when 'Long Sales Cycle (31+ Days)' then 3
end;

```
 
Finding: Only 11% of lost deals were instant rejections - the leads are well-qualified. But 45% dragged on 30+ days before going cold. **This is not a lead generation problem. It is a closing problem.**
 
**Q6 - Regional Revenue Efficiency**
The East region yields $1,349.02 in won revenue for every opportunity in the pipeline - the highest of any region. The metric used is `won_revenue_per_opportunity`, not just total revenue, to measure true conversion efficiency.
 
**Q7 - Deal Duration vs. Revenue by Product**
GTX Pro is the highest-revenue product ($3.5M) and also the fastest to close. GTK 500 takes the longest (64 days) and generates the least revenue - the worst risk-adjusted return in the portfolio.
 
**Q8 - Manager-Level Analysis**
Win rates are remarkably consistent across all managers, ranging only from 62.08% to 64.43%. But total revenue varies by 2× (Melvin Marxen $2.25M vs. Dustin Brinkmann $1.09M). When everyone closes at the same rate but revenues differ this much, the gap is deal size and account quality - not individual skill.
 
---
 
## ⚙️ Part 2: Power BI Dashboard

### Data Model
Built on a star schema with `sales_pipeline` as the central fact table, connected to three dimension tables: `products`, `accounts`, and `sales_teams`. Star schema chosen over a flat table to enable efficient cross-dimensional filtering without data redundancy.

### Power Query Transformations
Two columns were created in Power Query before loading into the data model:

- **Stage Order** - assigns a sort number to each deal stage (prospecting=1, engaging=2, won=3, lost=4) so visuals sort chronologically not alphabetically. Created here rather than DAX to avoid circular dependency errors.

- **Close Month / Close Month Name** - extracts month number and abbreviated name from close_date for time-based filtering across all pages.

---

### Key DAX Measures

**Core metrics**
```dax
Won Deals = 
    CALCULATE(COUNTROWS(pipeline), 
        pipeline[deal_stage] = "won")

Won/Lost = 
    CALCULATE(COUNTROWS(pipeline), 
        pipeline[deal_stage] IN {"won", "lost"})

Win Rate = DIVIDE([Won Deals], [Won/Lost], 0)

Total won Revenue = 
    CALCULATE(SUM(pipeline[close_value]), 
        pipeline[deal_stage] = "won")

Avg Deal Size = DIVIDE([Total won Revenue], [Won Deals], 0)
```

**Target calculation**
```dax
Target = [Avg Monthly Revenue] * 1.15
```
Target is dynamically calculated as average monthly revenue plus a 15% growth assumption. Updates automatically when the month slicer changes.

**Pipeline risk**
```dax
Days Open = 
    IF(
        ISBLANK(pipeline[engage_date]), BLANK(),
        IF(
            NOT(ISBLANK(pipeline[close_date])),
            DATEDIFF(pipeline[engage_date], 
                pipeline[close_date], DAY),
            DATEDIFF(pipeline[engage_date], 
                DATE(2017, 12, 31), DAY)
        )
    )

Pipeline Health = 
    IF(pipeline[deal_stage] IN {"won","lost"}, "Closed",
        IF(ISBLANK(pipeline[Days Open]), "Prospecting",
            IF(pipeline[Days Open] > 90, "Stale (>90)", 
                "Healthy Open")))
```
Pipeline Health categorizes every deal into one of four states. Closed deals are excluded from risk calculations. Open deals are flagged as Stale if they have been open more than 90 days, Prospecting if never engaged, or Healthy Open otherwise.
```dax
Projected Value = 
    IF(ISBLANK(pipeline[close_value]) || 
        pipeline[close_value] = 0,
        RELATED(products[sales_price]),
        pipeline[close_value])
```
For open deals with no close_value recorded, Projected Value falls back to the standard product sales_price from the Products table. This gives a realistic revenue estimate for the active pipeline without fabricating data.
```dax
% Pipeline at Risk = 
    VAR AtRiskRevenue = 
        CALCULATE(
            SUM(pipeline[Projected Value]), 
            pipeline[Pipeline Health] IN 
                {"Stale (>90)", "prospecting"})
    VAR TotalOpenRevenue = 
        CALCULATE(
            SUM(pipeline[Projected Value]), 
            pipeline[deal_stage] IN 
                {"prospecting", "engaging"})
    RETURN DIVIDE(AtRiskRevenue, TotalOpenRevenue, 0)
```
Divides the monetary value of all stale and ignored deals by the total active pipeline value. Result of 95.27% means only $230K of $4.82M active pipeline is currently healthy.

**Account analysis**
```dax
Revenue % Contribution = 
    DIVIDE(
        [Total won Revenue],
        CALCULATE(
            [Total won Revenue], 
            ALL(accounts[account])),
        0)
```
ALL() removes the account filter context to calculate each account's share against the true grand total not just the filtered subset.
```dax
Avg revenue per account = 
    DIVIDE(
        [Total won Revenue], 
        DISTINCTCOUNT(pipeline[account]), 
        0)
```

---

### Dashboard Pages

#### Page 1 - Executive Sales Performance
**Question:** Are we hitting targets and who is driving results?

Revenue target is calculated dynamically as average monthly revenue × 1.15. June was the strongest month at $1.34M i.e. 41% above the monthly average. The manager leaderboard reveals that Rocco Neubert generates the 2nd highest revenue but carries the lowest win rate - high volume, low efficiency.

<img width="4150" height="2400" alt="page1_executive_sales" src="https://github.com/user-attachments/assets/2f15e14e-a61e-41bc-b512-69ffcf2cafb8" />
---

#### Page 2 - Pipeline Risk & Leakage Diagnostic
**Question:** Where is active pipeline silently dying?

95% of the active pipeline ($4.59M of $4.82M total) is either stale or stuck in prospecting. Only $230K worth of deals are currently healthy. The drill-down matrix allows sales directors to identify risk exposure at the manager, agent, and individual deal level.

<img width="4150" height="2400" alt="page2_pipeline_risk" src="https://github.com/user-attachments/assets/39347841-b641-4208-918c-f66fe5ad878e" />


---

#### Page 3 - Product Performance
**Question:** What are we selling and what's making money?

GTX Pro leads total revenue across 9 of 10 sectors. GTK 500 has the highest average deal size at $26,765 but takes 64 days to close, the longest in the 
portfolio and a significant efficiency bottleneck. MG Special has the highest deal volume relative to revenue generated, a product worth reviewing for continued investment.

<img width="4150" height="2400" alt="page3_product_performance" src="https://github.com/user-attachments/assets/af98d878-c757-4c50-8046-e1256a42140f" />



---

#### Page 4 - Account & Market Analysis
**Question:** Who is buying and where is the opportunity?

Retail leads all sectors at $1.78M in won revenue. Kan-code is the highest contributing account at 3.59% of total revenue. Average revenue per account is $110.26K. The sector and series breakdown reveals GTX dominates across all markets at 73.45% of total series revenue.

<img width="4150" height="2400" alt="page4_account_market" src="https://github.com/user-attachments/assets/5e350430-04c5-40f2-9d03-f0d085b5c24b" />



---

## Repository Structure
```
CRM-Sales-Analytics/
│
├── README.md
├── SQL/
│   └── crm_cleaning_analysis.sql
├── Screenshots/
    ├── page1_executive_sales.png
    ├── page2_pipeline_risk.png
    ├── page3_product_performance.png
    └── page4_account_market.png
```

---
## Business Recommendations

- Set a 30-day follow-up rule - 45% of lost deals dragged on 30+ days. Flag any deal with no activity at the 30-day mark before more time is wasted
- Create a dedicated segment for lean high-revenue accounts - they close faster and spend more. Treating them like large enterprises is leaving money on the table  
- Review GTK 500's pitch or pricing - 64-day close time with the lowest revenue return means something is broken
---

*Built by Krishna Mallik | MySQL + Power BI | 2026*
