CREATE OR REPLACE TEMPORARY table feed_visits as 
        (select v.visit_id,
        v.marketing_region,
        CASE
            WHEN second_channel IN(
            'gpla', 'intl_gpla'
            ) THEN 1
            WHEN second_channel IN(
            'facebook_disp', 'facebook_disp_intl'
            ) THEN 2
            WHEN second_channel = 'instagram_disp' THEN 3
            WHEN second_channel IN(
            'bing_plas', 'intl_bing_plas'
            ) THEN 4
            WHEN second_channel in ('pinterest_disp','pinterest_disp_intl') THEN 5
            WHEN second_channel = 'affiliates' and (third_channel = 'affiliates_feed' or third_channel = 'affiliates_widget' ) THEN 6	
            WHEN second_channel in ('native_display','intl_native_display') and third_channel not like '%msan%' then 7
            ELSE 0
        END AS channel_int,
        reporting_channel_group,
        audience,
        engine, 
        tactic_high_level,
        tactic_granular,
        date(start_datetime) as date,
        from `etsy-data-warehouse-prod.buyatt_mart.visits_vw` v
        left join `etsy-data-warehouse-prod.buyatt_mart.channel_dimensions` cd using (utm_campaign, utm_medium, top_channel, second_channel, third_channel)
        where start_datetime >= '2020-01-01'
        and _date >= '2020-01-01'
        and reporting_channel_group in ('PLA', 'Display', 'Paid Social', 'Affiliates')
        AND (v.second_channel IN(
                     'gpla', 'intl_gpla', 'facebook_disp', 'bing_plas', 'intl_bing_plas', 'pinterest_disp', 'pinterest_disp_intl','instagram_disp', 'facebook_disp_intl', 'affiliates'
                   ) or (v.second_channel in ('native_display','intl_native_display') and third_channel not like '%msan%'))
          AND upper(b.utm_campaign) NOT LIKE '%_CUR_%' );
      

CREATE OR REPLACE table etsy-data-warehouse-dev.tnormil.charge_lt_mta as
(select date(b.receipt_timestamp) as date,
    b.receipt_id, 
    v.reporting_channel_group,
    v.engine,
    case when r2.receipt_id is not null then 1 else 0 end as charged_osa,
    r.channel,
    case when r.channel = 1 then 'PLA - Google - Paid'
    when r.channel in (2,3) then 'Paid Social - Facebook - Paid'
    when r.channel = 4 then 'PLA - Bing - Paid'
    when r.channel = 5 then 'Paid Social - Pinterest - Paid'
    when r.channel = 6 then 'Affiliates - Affiliates'
    when r.channel = 7 then 'Display - Google - Paid' end as channel_str,
    sum(b.external_source_decay_all) AS attr_receipt,
    #credit assigned to all chargeable receipts
    sum(case when r.acquisition_fee_usd is not null then b.external_source_decay_all end) AS attr_receipt_osa_channel,
    sum(b.external_source_decay_all * b.gms) AS attr_gms,
    #gms assigned to all chargeable receipts
    sum(case when r.acquisition_fee_usd is not null then b.external_source_decay_all * b.gms end) AS attr_gms_osa_channel,   
    sum(b.external_source_decay_all * c.attr_rev) AS attr_rev,
    min(v.date) as first_visit_date,
FROM  feed_visits    AS v
    INNER JOIN `etsy-data-warehouse-prod.buyatt_mart.attr_by_browser` AS b ON v.visit_id = b.o_visit_id
    INNER JOIN `etsy-data-warehouse-prod.buyatt_mart.buyatt_analytics_clv` AS c ON b.receipt_id = c.receipt_id
    LEFT OUTER JOIN `etsy-data-warehouse-prod.etsy_shard.ads_attributed_receipts` AS r ON b.receipt_id = r.receipt_id and v.channel_int = r.channel
    LEFT OUTER JOIN `etsy-data-warehouse-prod.etsy_shard.ads_attributed_receipts` AS r2 ON b.receipt_id = r2.receipt_id 
    group by 1,2,3,4,5,6,7);  

#CHANNEL LEVEL FACTORS
#receipts last touch osa : receipts mta ratio for chargeable orders only
with receipts_lt as
    (select date as order_date, date_trunc(date, year) as order_year,  extract(week from date) as order_weeek,  reporting_channel_group, engine, 
    count(distinct case when attr_receipt_osa > 0 then receipt_id end) as receipts_lt
    FROM `etsy-data-warehouse-dev.tnormil.charge_lt_mta` 
    group by 1,2,3),
attr_receipt as
    (SELECT date as order_date, reporting_channel_group, engine,
    sum(coalesce(attr_receipt_osa,0)) as attr_receipt_osa, 
    sum(coalesce(attr_receipt,0)) as attr_receipt,
    count(distinct case when attr_receipt_osa > 0 then receipt_id end) as receipts_mta 
    FROM `etsy-data-warehouse-dev.tnormil.charge_lt_mta` 
    group by 1,2,3)  
select a.*, b.attr_receipt_osa, b.attr_receipt, b.receipts_mta
from receipts_lt a
left join attr_receipt b using (order_date, reporting_channel_group, engine)
where b.attr_receipt_osa <> b.attr_receipt;

#total average channel credit across all receipts
with base as 
    (select date as order_date, reporting_channel_group,   engine,  receipt_id,  sum(attr_receipt) as attributed_receipts
    from etsy-data-warehouse-dev.tnormil.charge_lt_mta 
    group by 1,2,3,4,5,6 )
select date_trunc(order_date, year) as order_year,  extract(week from purchase_date) as order_weeek, reporting_channel_group, engine,  avg(attr_receipt) as attributed_receipts, stddev(attr_receipt) as attributed_receipts_std
from base 
group by 1,2,3;

