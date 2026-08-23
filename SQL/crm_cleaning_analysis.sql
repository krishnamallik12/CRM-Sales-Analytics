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
-- checking data types
desc accounts_staging;

-- Check for Duplicates
update accounts_staging
set account = trim(account);
      
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
where year_established>= year(curdate());

-- Standardizing sector names
select distinct sector from accounts_staging;
update accounts_staging
set sector = "technology"
where sector = "technolgy";




-- PRODUCTS_STAGING TABLE
desc products_staging;
select * from products_staging limit 100;

update products_staging
set product = trim(product);

-- Check for duplicate products
select product,series,sales_price
from (select product,series,sales_price, row_number() over(partition by product,series) as row_num
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
desc sales_teams_staging;
select * from sales_teams_staging limit 100;

-- Check if one agent works under multiple manager
select sales_agent, count(distinct manager) 
from sales_teams_staging
group by sales_agent
having count(distinct manager)>1;

select distinct regional_office
from sales_teams_staging;


-- SALES_PIPELINE_STAGING
select * from sales_pipeline_staging limit 100;

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

select deal_stage, count(*) as no_account
from sales_pipeline_staging
where account is NULL or account=''
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
		when account is NULL or account='' then 0
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

-- Exact duplicate check
select opportunity_id, sales_agent, product, account, deal_stage,
       engage_date, close_date, close_value, COUNT(*) as duplicate_count
from sales_pipeline_staging
group by opportunity_id, sales_agent, product, account, deal_stage,
         engage_date, close_date, close_value
having COUNT(*) > 1;
-- returned 0 rows , meaning no exact system duplication

-- Potentially duplicated opportunity IDs
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
-- Identify values that match none of the supported formats
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
select opportunity_id
from sales_pipeline_staging
where close_date < engage_date;


select count(*)
from sales_pipeline_staging
where deal_stage IN ("won", "lost") and close_value is NULL;

-- Referential-Integrity checks 
-- Accounts not found in master table
select distinct sp.account
from sales_pipeline_staging sp
left join accounts_staging a
    on sp.account = a.account
where sp.account is not NULL
  and trim(sp.account) <> ''
  and a.account is NULL;

-- Products not found in master table
select distinct sp.product
FROM sales_pipeline_staging sp
left join products_staging p
    on sp.product = p.product
where sp.product is not NULL
  and TRIM(sp.product) <> ''
  and p.product is NULL;

-- Sales agents not found in sales team master
select distinct sp.sales_agent
from sales_pipeline_staging sp
left join sales_teams_staging st
    on sp.sales_agent = st.sales_agent
where sp.sales_agent is not NULL
  and TRIM(sp.sales_agent) <> ''
  and st.sales_agent is NULL;

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

-- checking if any agent is have more than one manager
select * 
from sales_teams_staging a
join sales_teams_staging b 
on a.sales_agent = b.sales_agent
where a.manager <> b.manager;
-- It returned no rows hence every agent has one manager


-- Questions

-- Ques 1

-- How does closed-won revenue for each product change quarter-over-quarter in 2017, and what is the percentage change?
-- Quarter-over-Quarter (QoQ) Revenue by Product

with QuarterlySales as(
	select product, 
	year(close_date) as sales_year, 
	quarter(close_date) as sales_quarter, 
	sum(close_value) as quarterly_revenue
	from sales_pipeline_staging
	where deal_stage = "won" and close_date is not NULL
	group by product, year(close_date), quarter(close_date)
)
,QoQ_comparision as(
	select product, sales_year, sales_quarter,quarterly_revenue,
	lag(quarterly_revenue) over(partition by product order by sales_year,sales_quarter) as prev_quarter_revenue
	from QuarterlySales
)
select product,
sales_year,
sales_quarter,
quarterly_revenue,
prev_quarter_revenue,
concat(round(((quarterly_revenue - prev_quarter_revenue)/nullif(prev_quarter_revenue,0))*100,2),'%') as percent_change from QoQ_comparision 
;

-- Ques 2
-- Agent-level analysis:
-- Which sales agents generated the highest closed-won revenue, and how does their average deal duration compare with the overall average?

with overall_avg as (
	select avg(datediff(close_date,engage_date)) as overall_avg_deal_duration
	from sales_pipeline_staging
	where deal_stage = "won" 
		  and close_value is not NULL
		  and close_date is not NULL
		  and engage_date is not null
)
select sales_agent,
sum(close_value) as total_revenue_generated, 
count(*) as won_deals,
round(avg(datediff(close_date,engage_date)),2) as agent_avg_deal_duration,
round((select overall_avg_deal_duration from overall_avg),2) as overall_avg_deal_duration,
round((avg(datediff(close_date,engage_date)) - (select overall_avg_deal_duration from overall_avg)),2) as difference_from_company_avg
from sales_pipeline_staging
where deal_stage = "won" 
  and close_value is not NULL
  and close_date is not NULL
  and engage_date is not NULL
group by sales_agent
order by total_revenue_generated desc
;

-- Sales Agent: Darcel Schlecht generated the highest revenue and closed the deals 2 days faster than the overall average. 

-- Ques 3
-- Which sectors generate the highest closed-won revenue, and how do their win rates, deal volumes, and average won deal values compare?

select 
    a.sector,
    sum(case when sp.deal_stage = 'won' then sp.close_value else 0 end) as closed_won_revenue,
    count(case when sp.deal_stage = 'won' then 1 end) as won_deals,
    round(count(case when sp.deal_stage = 'won' then 1 end)/nullif(count(case when sp.deal_stage in ('won','lost') then 1 end),0) * 100,2) as win_rate_percentage,
    round(sum(case when sp.deal_stage = 'won' then sp.close_value else 0 end)/nullif(count(case when sp.deal_stage = 'won' then 1 end),0),2) as avg_won_deal_value
from sales_pipeline_staging sp
inner join accounts_staging a
    on sp.account = a.account
where sp.account is not null
group by a.sector
order by closed_won_revenue desc;

-- Ques 4
-- Which accounts generate the most closed-won revenue, and how does their win rate compare?

select account,
count(case when deal_stage = 'won' then 1 end) as total_won_deals,
sum(case when deal_stage = 'won' then close_value else 0 end) as total_won_revenue,
round((count(case when deal_stage = 'won' then 1 end) / 
    nullif(count(case when deal_stage in ('won','lost') then 1 end),0))*100,2) as win_rate
from sales_pipeline_staging
where account is not null
group by account
order by total_won_revenue desc;



-- Ques 5
-- How long do lost opportunities typically remain in the sales process after entering the engaging stage?
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

-- Only about 11.4% of Lost opportunities were closed within the first two days after engagement. 
-- A significant share of Lost opportunities remain open for more than 30 days, which may indicate an opportunity to improve qualification or earlier disengagement.
-- The largest category was Lost opportunities that remained open for more than 30 days, representing about 45.6% of all Lost opportunities.
-- This suggests that a substantial proportion of opportunities are remaining active for a relatively long period before ultimately being Lost.

-- Ques 6
-- How does regional pipeline performance compare in terms of Won/Lost deals, closed-won revenue, and closed-won revenue generated per opportunity?


select *
from sales_teams_staging a, sales_teams_staging b
where a.sales_agent=b.sales_agent
and a.regional_office <> b.regional_office;

select 
    st.regional_office,
    sum(case when s.deal_stage = 'won' then 1 else 0 end) as won_deals,
    sum(case when s.deal_stage = 'lost' then 1 else 0 end) as lost_deals,
    round(sum(case when s.deal_stage = 'won' then s.close_value else 0 end),2) as total_won_revenue,
    round(sum(case when s.deal_stage = 'won' then s.close_value else 0 end)
    /nullif(count(case when s.deal_stage in ('won','lost') then 1 end),0),2) as won_revenue_per_completed_opportunity
from sales_pipeline_staging s
join sales_teams_staging st
    on s.sales_agent = st.sales_agent
group by st.regional_office
order by won_revenue_per_completed_opportunity desc;

-- Ques 7
-- How do products differ in closed-won revenue, deal volume, deal value, and average closing time?

select 
    product,
    sum(close_value) as total_won_revenue,
    count(*) as won_deals,
    round(avg(close_value),2) as avg_won_deal_value,
    round(avg(datediff(close_date,engage_date)),2) as avg_close_time
from sales_pipeline_staging
where deal_stage = 'won'
  and close_date is not null
  and engage_date is not null
group by product
order by total_won_revenue desc;

-- Ques 8
-- Manager-level analysis:
-- How does sales performance vary by manager in terms of win rate and closed-won revenue across regions?

select 
    st.manager,
    st.regional_office,
    sum(case when s.deal_stage = 'won' then s.close_value else 0 end) as total_won_revenue,
    count(case when s.deal_stage = 'won' then 1 end) as won_deals,
    count(case when s.deal_stage in ('won','lost') then 1 end) as completed_deals,
    round(count(case when s.deal_stage = 'won' then 1 end)/nullif(count(case when s.deal_stage in ('won','lost') then 1 end),0) * 100,2) as win_rate
from sales_pipeline_staging s
left join sales_teams_staging st
    on s.sales_agent = st.sales_agent
group by st.manager, st.regional_office
order by total_won_revenue desc;


