#google performance 

begin

create temp table metro_dma_performance as  
(with base as (
    select
        clv.purchase_date, 
        clv.receipt_id, 
        clv.buyer_type,
        sum(attr_rev * external_source_decay_all) as attr_rev
    from `etsy-data-warehouse-prod.buyatt_mart.buyatt_analytics_clv` clv
    join  `etsy-data-warehouse-prod.buyatt_mart.attr_by_browser` ab using (receipt_id)
    join etsy-data-warehouse-prod.buyatt_mart.visits v on ab.o_visit_id = v.visit_id
    join etsy-data-warehouse-prod.buyatt_mart.channel_dimensions cd using (utm_campaign,
        utm_medium,
        top_channel,
        second_channel,
        third_channel)
    where purchase_date>='2022-01-01' 
        #and engine = 'Google - Paid'
        and marketing_region = 'US'
    group by 1,2,3
    order by 1,2,3),
geos as (
    select
        postal_code,
        count(distinct metro_code) as counts
    from `etsy-data-warehouse-prod.geoip.lite_city_location`
    group by 1
    having count(distinct metro_code)=1
    order by 1),
receipts as (
    select a.*, 
        zip as buyer_zip,
        metro_code as dma,
        mapped_user_id
    from base a 
    join `etsy-data-warehouse-prod.transaction_mart.all_receipts` b 
    using (receipt_id)
    join geos c 
    on b.zip=c.postal_code
    join ( select distinct postal_code, metro_code from `etsy-data-warehouse-prod.geoip.lite_city_location` ) d
    using (postal_code)
    where country_id=209
    )
select purchase_date as date, 
    dma,
    sum(attr_rev) as etsy_revenue,
    sum(coalesce(case when buyer_type like 'new%' then attr_rev end,0)) as etsy_new_revenue,
    sum(coalesce(case when buyer_type not like 'new%' then attr_rev end,0)) as etsy_existing_revenue,
    count(distinct mapped_user_id) as buyers
from receipts 
group by 1,2 order by 1);

/*
create temp table metro_dma_spend as
(select Day as date, substr(cast(Metro_area_code as string), 4) as dma, Clicks, Cost, Impressions
from etsy-data-warehouse-dev.tnormil.metro_dma);

select coalesce(p.date, s.date) as date, coalesce(p.dma, s.dma) as geo, coalesce(etsy_revenue,0) as response, coalesce(Cost,0) as cost, coalesce(Clicks,0) as clicks, coalesce(Impressions,0) as impressions
from metro_dma_performance p
full outer join metro_dma_spend s using (date, dma);
*/

create temp table metro_dma_spend as
(select day as date, l.string_field_2 as dma, sum(Cost__Converted_currency_) as cost,
 sum(Impr_) as impressions, sum(clicks) clicks
from etsy-data-warehouse-dev.tnormil.google_metro_dma_cost g
    left join etsy-data-warehouse-dev.tnormil.metro_lookup l on g.DMA_Region__Matched_ = l.string_field_0	
-- https://docs.google.com/spreadsheets/d/1NtUE_g1k3b3NIAcEnW0ggdr2wcIhkuvxfpXQMkmE0Qo/edit#gid=144236520
group by 1,2);

create or replace table etsy-data-warehouse-dev.tnormil.google_metro_dma_perf as
(select coalesce(p.date, s.date) as date, coalesce(p.dma, s.dma) as geo, coalesce(etsy_revenue,0) as response, coalesce(Cost,0) as cost, coalesce(buyers,0) as buyers, 
from etsy-bigquery-adhoc-prod._script8f304b9c57bba252cd88b68fabdfa1e8dabaf64a.metro_dma_performance p
full outer join metro_dma_spend s using (date, dma));

end;
