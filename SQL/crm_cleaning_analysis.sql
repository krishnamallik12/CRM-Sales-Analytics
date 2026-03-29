create database crm;
use crm;

show tables; 

-- first thing we want to do is create staging tables. 
-- This is the one we will work in and clean the data. We want a table with the raw data in case something happens

-- ACCOUNTS_STAGING
Create table accounts_staging
like accounts;

insert accounts_staging
select * from accounts;

select * from accounts_staging
LIMIT 1000;

-- ------------------------------------------------------------------------------------

-- PRODUCTS STAGING
Create table products_staging
like products;

insert products_staging
select * from products;

select * from products_staging
LIMIT 1000;

-- ------------------------------------------------------------------------------------

-- SALES PIPELINE STAGING
Create table sales_pipeline_staging
like sales_pipelines;

insert sales_pipeline_staging
select * from sales_pipelines;

select * from sales_pipeline_staging
LIMIT 1000;


-- ------------------------------------------------------------------------------------

-- SALES TEAM STAGING

Create table sales_teams_staging
like sales_teams;

insert sales_teams_staging
select * from sales_teams;

select * from sales_teams_staging
LIMIT 1000;


-- ------------------------------------------------------------------------------------

-- DATA CLEANING
-- Check for Duplicates

      
select account, sector, year_established, revenue, employees, office_location, subsidiary_of,count(*)
from accounts_staging
group by account, sector, year_established, revenue, employees, office_location, subsidiary_of
having count(*)>1;

-- checking if same company name appearing multiple times

select count(*) 
from accounts_staging
where trim(account) = ' ' or 
      account is NULL ;
      
select *
from(
	select account,row_number() over(partition by account) as row_num
	from accounts_staging) duplicate_company
where row_num>1;

-- Checking any missing segmentation fields and Invalid values

-- ACCOUNTS_STAGING TABLE
select count(*)
from accounts_staging
where trim(sector) = '' or 
      sector is NULL;
      
select account
from accounts_staging
where employees<=0;

select account
from accounts_staging
where revenue<=0;

select account
from accounts_staging
where year_established>= curdate();

-- Standardizing sector names
  
update accounts_staging
set sector = "technology"
where sector = "technolgy";

update accounts_staging
set account = trim(account);



-- PRODUCTS_STAGING TABLE

select * from products_staging;

update products_staging
set product = trim(product);

-- Check for duplicate products
select product
from (select product, row_number() over(partition by product,series) as row_num
      from products_staging) product_duplicate
where row_num>1;

-- Check for missing prices
select product
from products_staging
where sales_price = 0 or
      sales_price is NULL;

-- Checking for inconsistent product and series names
select distinct product 
from products_staging; 

select distinct series 
from products_staging; 


-- SALES_TEAMS_STAGING TABLE

select * from sales_teams_staging;

-- Check if one agent works under multiple manager
select sales_agent, count(manager) 
from sales_teams_staging
group by sales_agent
having count(manager)>1;

select distinct regional_office
from sales_teams_staging;


-- SALES_PIPELINE_STAGING
select * from sales_pipeline_staging;

-- checking datatypes
describe sales_pipeline_staging;

select count(*) from sales_pipeline_staging;

select count(opportunity_id)
from sales_pipeline_staging
where opportunity_id is null; 

-- Standardising 
update sales_pipeline_staging
set deal_stage = lower(trim(deal_stage));

update sales_pipeline_staging
set sales_agent = trim(sales_agent),
    account = trim(account),
    product = trim(product);

-- Checking for NULL/MISSING accounts
select count(*) 
from sales_pipeline_staging
where trim(account) = '' or account is NULL;


-- Total rows in the table are 8800
-- There are 1425 oppurtunities which has no account. Therefore, approx 16.2% of the data.

-- Diagnosing why accounts are null
-- Checking if these rows are:
-- Open deals
-- Early stage deals
-- Lost deals
-- Specific agents
-- Specific product

select deal_stage, count(*)
from sales_pipeline_staging
where account is NULL 
group by deal_stage;

-- Since all NULL accounts are in early stages:
-- Prospecting, Engaged
-- And NOT in Won / Lost
-- This strongly suggests:
-- These are early-stage pipeline records
-- Account not yet formally created or linked
-- This is operational CRM behavior

alter table sales_pipeline_staging
add column has_account tinyint;

update sales_pipeline_staging
set has_account =
    case
		when account is NULL then 0
        else 1
	end ;
        
-- Verifying the changes
select has_account,count(*)
from sales_pipeline_staging
group by has_account;

 select count(opportunity_id) 
from sales_pipeline_staging
where trim(sales_agent) = '' or sales_agent is null;

select count(opportunity_id) 
from sales_pipeline_staging
where trim(product) = '' or product is null;

select opportunity_id, sales_agent, account, deal_stage,
str_to_date(engage_date,"%d-%m-%y")
from sales_pipeline_staging;

select opportunity_id 
from sales_pipeline_staging
where opportunity_id is null or trim(opportunity_id) = '';

-- checking different deal stages
select distinct deal_stage
from sales_pipeline_staging;

-- Are there Won deals with NULL close_value?
select close_value, deal_stage
from sales_pipeline_staging
where deal_stage = "won" and (close_value is NULL or close_value = 0);
-- Result: 0 rows — all won deals have valid close values

-- Duplicate check

-- Check Exact Duplicates (Make sure the system didn’t accidentally duplicate rows)

select opportunity_id,sales_agent,product,account,deal_stage,engage_date,close_date,close_value,count(*)
from sales_pipeline_staging
group by opportunity_id,sales_agent,product,account,deal_stage,engage_date,close_date,close_value
having count(*)>1;
-- returned 0 rows , meaning no exact system duplication

select opportunity_id, count(*)
from sales_pipeline_staging
group by opportunity_id
having count(*)>1;


/* ============================================================
   DATE STANDARDIZATION & VALIDATION
   Objective:
   1. Detect mixed date formats
   2. Identify invalid date values
   3. Standardize to DATE datatype (YYYY-MM-DD)
   ============================================================ */


/* ---------------------------
   ENGAGE DATE
   --------------------------- */

/* Step 1: Identify invalid or non-convertible date values */
select engage_date
from sales_pipeline_staging
where engage_date is not null
  and trim(engage_date) <> ''
  and str_to_date(engage_date, '%Y-%m-%d') is null
  and str_to_date(engage_date, '%d-%m-%Y') is null
  and str_to_date(engage_date, '%m/%d/%Y') is null
  and str_to_date(engage_date, '%Y/%m/%d') is null;

-- there are no invalid engage dates
-- Since the data type of the engage date is not DATE, we will change the type but first we will standardize them.

/* Step 2: Standardize date formats */
update sales_pipeline_staging
set engage_date =
    case
        when str_to_date(engage_date, '%Y-%m-%d') is not null
            then str_to_date(engage_date, '%Y-%m-%d')
        when str_to_date(engage_date, '%d-%m-%Y') is not null
            then str_to_date(engage_date, '%d-%m-%Y')
        when str_to_date(engage_date, '%m/%d/%Y') is not null
            then str_to_date(engage_date, '%m/%d/%Y')
        when str_to_date(engage_date, '%Y/%m/%d') is not null
            then str_to_date(engage_date, '%Y/%m/%d')
        else null
    end;


/* Step 3: Convert column to DATE datatype */
alter table sales_pipeline_staging
modify engage_date date;



/* ---------------------------
   CLOSE DATE
   --------------------------- */

/* Step 1: Identify invalid or non-convertible date values */
select close_date
from sales_pipeline_staging
where close_date is not null
  and trim(close_date) <> ''
  and str_to_date(close_date, '%Y-%m-%d') is null
  and str_to_date(close_date, '%d-%m-%Y') is null
  and str_to_date(close_date, '%m/%d/%Y') is null
  and str_to_date(close_date, '%Y/%m/%d') is null;


/* Step 2: Standardize date formats */
update sales_pipeline_staging
set close_date =
    case
        when str_to_date(close_date, '%Y-%m-%d') is not null
            then str_to_date(close_date, '%Y-%m-%d')
        when str_to_date(close_date, '%d-%m-%Y') is not null
            then str_to_date(close_date, '%d-%m-%Y')
        when str_to_date(close_date, '%m/%d/%Y') is not null
            then str_to_date(close_date, '%m/%d/%Y')
        when str_to_date(close_date, '%Y/%m/%d') is not null
            then str_to_date(close_date, '%Y/%m/%d')
        else null
    end;

/* Step 3: Convert column to DATE datatype */
alter table sales_pipeline_staging
modify close_date date;


/* ---------------------------
   Final Logical Validation
   --------------------------- */

/* Ensure no opportunity closes before it is engaged */
SELECT opportunity_id
FROM sales_pipeline_staging
WHERE close_date < engage_date;


select count(*)
from sales_pipeline_staging
where deal_stage IN ("won", "lost") and close_value is NULL;

update sales_pipeline_staging sp
left join products_staging p
on sp.product = p.product
set sp.close_value = Case
	when sp.deal_stage = "won" and (sp.close_value is NULL or sp.close_value<=0) then p.sales_price
    when sp.deal_stage = "lost" then 0
    else sp.close_value
    end
 ;
      
-- check for revenue validation
select count(*)
from sales_pipeline_staging
where deal_stage = "won" and close_value <= 0 ;


select count(*)
from sales_pipeline_staging
where deal_stage = "lost" and close_value <> 0 ;


-- Questions

-- Ques 1
-- How does closed-won revenue for each product compare between the most recent quarter and the previous quarter, and what is the percentage change?
-- Quarter-over-Quarter (QoQ) Revenue by Product

with QuarterlySales as(
	select product, 
	year(close_date) as sales_year, 
	quarter(close_date) as sales_quarter, 
	sum(close_value) as current_revenue
	from sales_pipeline_staging
	where deal_stage = "won" and close_date is not NULL
	group by product, year(close_date), quarter(close_date)
)
,QoQ_comparision as(
	select product, sales_year, sales_quarter,current_revenue,
	lag(current_revenue) over(partition by product order by sales_year,sales_quarter) as prev_quarter_revenue
	from QuarterlySales
)
select product,
sales_year,
sales_quarter,
current_revenue,
prev_quarter_revenue,
concat(round(((current_revenue - prev_quarter_revenue)/prev_quarter_revenue)*100,2),'','%') as percent_change from QoQ_comparision qc
;

-- Ques 2
-- Agent-level analysis:
-- Which sales agents generated the highest closed-won revenue
-- what does their average deal duration compare to the overall average?

with company_avg as (
	select avg(datediff(close_date,engage_date)) as company_avg_deal_duration
	from sales_pipeline_staging
	where deal_stage = "won" 
		  and close_date is not NULL
		  and engage_date is not null
)
select sales_agent,
sum(close_value) as total_revenue_generated, 
round(avg(datediff(close_date,engage_date)),2) as agent_avg_deal_duration,
round((select company_avg_deal_duration from company_avg),2) as company_avg_deal_duration
from sales_pipeline_staging
where deal_stage = "won" and close_value is not null
group by sales_agent
order by sum(close_value) desc
;

-- Ques 3
-- Which lean, capital-efficient accounts (below avg headcount but above avg company revenue) generate the highest closed-won revenue?
--    These accounts have high revenue-per-employee ratios, suggesting
--    streamlined decision-making and stronger purchasing power.
--    Isdom, Codehow and Gekko & Co lead this segment 
--    These accounts should be prioritized for upselling and retention given their
--    demonstrated spending capacity relative to their team size.
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


-- Ques 4
-- Which accounts generate the most deal volume vs actual revenue?
--    Identifies accounts consuming disproportionate sales effort 
--    relative to their revenue contribution
select account,
count(case when deal_stage='won' then 1 end) as Total_won_deals,
count(case when deal_stage='lost' then 1 end) as Total_lost_deals,
sum(case when deal_stage= 'won' then close_value else 0 end) as Total_revenue,
round(sum(case when deal_stage= 'won' then close_value else 0 end)/nullif(count(case when deal_stage='won' then 1 end),0),2) as revenue_per_won_deal,
round((count(case when deal_stage='won' then 1 end) / 
	nullif(count(case when deal_stage in ('won','lost') then 1 end),0))*100,2) as win_rate
from sales_pipeline_staging
where account is not NULL
group by account
order by win_rate desc;


-- Ques 5
-- How long does it typically take for an unsuccessful deal to drop off after initial engagement?
with categorized_loss as(
	select opportunity_id,
    case
		when datediff(close_date,engage_date)<=2 then 'Instant Rejection (0-2 Days)'
        when datediff(close_date,engage_date) between 3 and 30 then 'Short Engagement (3-30 Days)'
        else 'Prolonged Disengagement (30+ Days)'
	end as drop_off_category
    from sales_pipeline_staging
    where deal_stage = 'lost')
select drop_off_category, count(opportunity_id) as Total_lost_deals,
round((count(opportunity_id)/sum(count(opportunity_id)) over())*100,2) as Lost_Percent
from categorized_loss 
group by drop_off_category;

-- The data shows that our leads are highly qualified—only 11% instantly reject us. 
-- However, our sales team is bleeding time and resources. 
-- Nearly half of all our lost deals are 'Prolonged Disengagements,' meaning our reps are spending over a month
-- doing demos and negotiations only for the client to ghost them. 
-- We don't have a lead-generation problem; we have a closing problem.

-- Ques 6
-- Which regions generate the highest closed-won revenue per opportunity?

-- checking if any agent is have more than one manager
select * 
from sales_teams_staging a
join sales_teams_staging b 
on a.sales_agent = b.sales_agent
where a.manager <> b.manager;
-- It returned no rows hence every agent has one manager

select regional_office,
round(sum(case when deal_stage = 'won' then close_value else 0 end)/count(opportunity_id),2) as won_revenue_per_opportunity
from sales_pipeline_staging s
join sales_teams_staging st
on s.sales_agent = st.sales_agent 
group by st.regional_office
order by won_revenue_per_opportunity desc;

-- Ques 7
-- Which products close fastest on average, and how does deal duration relate to closed-won revenue?

select product,
sum(close_value) as total_revenue,
round(avg(datediff(close_date,engage_date)),2) as close_time_average
from sales_pipeline_staging
where deal_stage = 'won'
group by product
order by total_revenue desc;
-- GTK 500 was identified as a major efficiency bottleneck, 
-- taking a portfolio-high 64 days to close while yielding bottom-tier total revenue.

-- Ques 8
-- Manager-level analysis:
-- How does sales performance vary by manager in terms of win rate and closed-won revenue across regions?
-- Evaluates team-level win rates and revenue across geographic offices

select st.manager, sum(case when s.deal_stage = 'won' then s.close_value else 0 end) as total_revenue,
st.regional_office, 
round((count(case when s.deal_stage = 'won' then 1 end)/count(case when s.deal_stage in ('won','lost') then 1 end))*100,2) as win_rate
from sales_pipeline_staging s
left join sales_teams_staging st
on s.sales_agent = st.sales_agent
group by st.manager,st.regional_office
order by win_rate desc;




