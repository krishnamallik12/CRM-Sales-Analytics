# CRM Sales & Pipeline Diagnostic
**Tech Stack:** MySQL · Power BI · Power Query · DAX

Key findings:
- Identified $4.59M (95%) of active pipeline at risk of being lost
- Discovered sales team spends 30+ days on 45% of deals that never close
- Found lean companies generate disproportionately high revenue challenging - the big company = big deal assumption

---

## Project Overview

This is an end-to-end analytics project built on a raw B2B CRM dataset containing 8,800 sales opportunities across 4 tables, covering a B2B technology company's sales activity from 2017 (March to December) across three regional offices. Original dataset included late 2016 data which was excluded 
to maintain full-year consistency in the analysis. 
The goal was to go beyond surface-level reporting and answer the questions a sales director actually loses sleep over:

- Are we hitting revenue targets and who is driving it?
- Where is our active pipeline silently dying?
- Which products and markets are worth our sales effort?

The project covers the complete pipeline:
**Raw Data → SQL Cleaning → Data Model → Power BI Dashboard**

---

## The Business Problem

The sales organization had no clear visibility into pipeline health. Deals were stalling, revenue was at risk, and nobody could pinpoint exactly where the sales process was breaking down. This project was built to diagnose those problems with data not gut feeling.

---

## Part 1: SQL Data Cleaning & Analysis (MySQL)

### Why Staging Tables First

Before touching the raw data I created a copy of every table as a staging table. This meant if I accidentally deleted or corrupted something during cleaning, the original data was always safe. Every transformation happened on the staging tables only.

### What I Cleaned

- **Date standardization:** The engage_date and close_date columns had mixed formats across rows. I detected every format variation and standardized everything to a clean DATE datatype using STR_TO_DATE() with multiple format patterns.

- **Close value standardization:** Applied a defensive UPDATE using a LEFT JOIN to the Products table to enforce consistent close_value logic across all deal stages:
  - Won deals: fallback to standard product sales_price if close_value was missing or zero (validation confirmed no such cases existed acts as safety net for future loads)
  - Lost deals: explicitly set to 0 to ensure clean revenue aggregations
  - Open deals: left as NULL, no revenue assumed for unclosed deals

- **NULL account investigation:** 1,425 opportunities (16.2% of the dataset) had no linked account. Instead of deleting them I investigated why. The finding: every single NULL account record was in either Prospecting or Engaging stage, never in Won or Lost. This is normal CRM behavior, early stage leads that haven't been formally linked to an account yet. I flagged these with a has_account column (0/1) and kept them in the dataset.

- **Sector name fix:** Found a typo "technolgy" standardized to "technology" across all affected rows.

### A Key CRM Discovery

Every lost deal in the dataset had both an engage_date and a close_date meaning our sales team made contact before the deal was marked lost. This revealed something important: leads that were contacted but never responded were NOT being marked as lost. They were sitting in Prospecting indefinitely, clogging the pipeline with dead weight that looks like active opportunity but isn't.

---

## SQL Business Analysis (8 Questions)

### The Most Important Finding — Q5
```sql
-- How long does it take for an unsuccessful deal to drop off after initial engagement?

with categorized_loss as(
	select opportunity_id,
        case
		when datediff(close_date,engage_date)<=2 then 'Instant Rejection (0-2 Days)'
                when datediff(close_date,engage_date) between 3 and 30 then 'Short Engagement (3-30 Days)'
        	else 'Prolonged Disengagement (30+ Days)'
	end as drop_off_category
        from sales_pipeline_staging
        where deal_stage = 'lost')
select drop_off_category, 
count(opportunity_id) as Total_lost_deals,
round((count(opportunity_id)/sum(count(opportunity_id)) over())*100,2) as Lost_Percent
from categorized_loss 
group by drop_off_category;
```

**Finding:** Only 11% of lost deals were instant rejections meaning our leads are well qualified. But 45% of lost deals dragged on for 30+ days before going cold. The sales team is spending over a month on deals that will never close.

**This is not a lead generation problem. It is a closing problem.**

---

### Q1 — Quarter over Quarter Revenue by Product

Used LAG() window function to compare each product's revenue against the previous quarter - identifying which products are growing and which are declining.

**Finding:** Nearly every product saw a violent revenue spike in Q2 (e.g., GTK 500 surged 621%, GTX Pro up 186%), followed by sharp contractions or stagnation in Q3 and Q4.

---

### Q2 — Agent-Level Efficiency
**Finding:** High revenue does not inherently require longer sales cycles. The top-performing sales agent (Darcel Schlecht) is a massive outlier generating $1.15M (more than double the next closest agent) while closing deals in just 49.4 days, which is a full 2 days faster than the company average.

---

### Q3 — High Value Accounts Hidden in Small Companies
```sql
with benchmarks as(
	select avg(employees) as avg_employees, 
	avg(revenue) as avg_revenue
	from accounts_staging)
select sp.account, 
a.revenue as revenue_in_millions,
a.employees, 
sum(sp.close_value) as total_sales,
round(sum(sp.close_value)/(a.employees),2) as sales_per_employee
from sales_pipeline_staging sp
join accounts_staging a
	on sp.account = a.account
cross join benchmarks
where a.employees< benchmarks.avg_employees
      and a.revenue> benchmarks.avg_revenue
      and sp.deal_stage ="won"
group by sp.account,a.employees, a.revenue 
order by sum(sp.close_value) desc;
```

**Finding:** Companies with fewer employees than average but higher company revenue than average generated some of the highest sales figures. Lean organizations have faster decision-making and stronger purchasing power, these accounts should be prioritized for upselling and retention.

---

### Q4 — Account Efficiency Analysis

Compared won deals, lost deals, total revenue and win rate per account to identify which accounts consume the most sales effort relative to their actual revenue contribution.

**Finding:** Total revenue does not equal sales efficiency. While Kan-code drives the most total volume, their win rate is only 61.5%. Conversely, accounts like Rangreen and Goodsilron boast incredible win rates of 75% and 73.8% respectively.

---

### Q6 — Regional Revenue Efficiency
```sql
select regional_office,
round(sum(case when deal_stage = 'won' then close_value else 0 end)/count(opportunity_id),2) as won_revenue_per_opportunity
from sales_pipeline_staging s
join sales_teams_staging st
on s.sales_agent = st.sales_agent 
group by st.regional_office
order by won_revenue_per_opportunity desc;
```
**Finding:** The East region is the most efficient at converting raw pipeline into dollars, yielding a true value of $1,349.02 for every opportunity.

---

### Q7 — Deal Duration vs. Revenue by Product

**Finding:** Expensive doesn't mean hard to sell. The priciest product (GTX Pro) is actually the fastest seller and the biggest moneymaker ($3.5M). On the other side, the GTK 500 takes the longest to sell (64 days) but brings in the least amount of money.

---

### Q8 — Manager-Level Analysis

**Finding:** Win rates are remarkably consistent across all managers and regions ranging only from 62.08% to 64.43%. No single manager has a meaningful edge in closing ability. However total revenue varies by 2x between the highest (Melvin Marxen $2.25M) and lowest (Dustin Brinkmann $1.09M) performers. When everyone wins at the same rate but revenues differ this much, the gap comes from deal size and account quality, not individual skill

---

## ⚙️ Part 2: Power BI Dashboard

### Data Model
The dashboard is built on a star schema with the `sales_pipeline` table as the central fact table, connected to three dimension tables:
- `products` — linked via product name
- `accounts` — linked via account name  
- `sales_teams` — linked via sales_agent name
A star schema was chosen over a flat table to enable efficient filtering across dimensions without data redundancy.

### Power Query Transformations
Two columns were created in Power Query before loading into the data model:

- **Stage Order** — assigns a sort number to each deal stage (prospecting=1, engaging=2, won=3, lost=4) so visuals sort chronologically not alphabetically. Created here rather than DAX to avoid circular dependency errors.

- **Close Month / Close Month Name** — extracts month number and abbreviated name from close_date for time-based filtering across all pages.

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

#### Page 1 — Executive Sales Performance
**Question:** Are we hitting targets and who is driving results?

Revenue target is calculated dynamically as average monthly revenue × 1.15. June was the strongest month at $1.34M i.e. 41% above the monthly average. The manager leaderboard reveals that Rocco Neubert generates the 2nd highest revenue but carries the lowest win rate - high volume, low efficiency.

<img width="4150" height="2400" alt="crm_dashboard-1" src="https://github.com/user-attachments/assets/1d9bde27-7911-4290-9f21-4a7dee6dab93" />

---

#### Page 2 — Pipeline Risk & Leakage Diagnostic
**Question:** Where is active pipeline silently dying?

95% of the active pipeline ($4.59M of $4.82M total) is either stale or stuck in prospecting. Only $230K worth of deals are currently healthy. The drill-down matrix allows sales directors to identify risk exposure at the manager, agent, and individual deal level.

<img width="4150" height="2400" alt="crm_dashboard-2" src="https://github.com/user-attachments/assets/2b3f3e75-93cb-4262-86cb-f313f930b906" />

---

#### Page 3 — Product Performance
**Question:** What are we selling and what's making money?

GTX Pro leads total revenue across 9 of 10 sectors. GTK 500 has the highest average deal size at $26,765 but takes 64 days to close, the longest in the 
portfolio and a significant efficiency bottleneck. MG Special has the highest deal volume relative to revenue generated, a product worth reviewing for continued investment.

<img width="4150" height="2400" alt="crm_dashboard-3" src="https://github.com/user-attachments/assets/2a6c50cf-053f-4e8a-8374-caa3eddea92f" />

---

#### Page 4 — Account & Market Analysis
**Question:** Who is buying and where is the opportunity?

Retail leads all sectors at $1.78M in won revenue. Kan-code is the highest contributing account at 3.59% of total revenue. Average revenue per account is $110.26K. The sector and series breakdown reveals GTX dominates across all markets at 73.45% of total series revenue.

<img width="4150" height="2400" alt="crm_dashboard-4" src="https://github.com/user-attachments/assets/90acd821-f39a-4e9b-bff1-bcebb8d46d35" />


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

## What I Learned

- Always create staging tables before cleaning.
- 16.2% of pipeline records had no linked account. Deleting them would have been wrong — investigating why revealed a real CRM behavior pattern worth preserving
- 95% pipeline at risk sounds alarming but becomes fully defensible once the methodology is documented clearly
- High deal size does not always mean high efficiency, GTK 500 proves that

---

*Built by Krishna Mallik | MySQL + Power BI | 2026*
