# create channel_cost for better sql optimization
alter table ts.mkt_data
add column channel_cost DECIMAL(10, 3)

update ts.mkt_data
set channel_cost = 
    case 
        when channel = 'SMS' then 0.050 
        when channel = 'Email' then 0.075 
    end;

# create step_order
alter table ts.mkt_data 
add column step_order int ;
  
update ts.mkt_data 
set step_order = 
	case 	when last_step = 'received' then 0
            when last_step = 'bounced' then 1
            when last_step = 'sawreview' then 2
            when last_step = 'addedtocart' then 3
            when last_step = 'paymentpage' then 4
            when last_step = 'purchased' then 5
        end;
         
       
# check send_date
select distinct send_date
from ts.mkt_data md 
order by send_date 

# #msg, total cost, total profit
select age_range , channel 
	, count(id) as 'messages'
	, (count(channel)*channel_cost + 18*sum(nb_units)) as cost
	, (sum(order_value) - count(channel)*channel_cost - 18*sum(nb_units)) as profit
from ts.mkt_data md 
group by age_range , channel
order by age_range , channel 

# số lượng gửi mail, sms 
select c.age_range, channel, round((c.ch / t.tt) * 100, 2) AS percent
from 
	(
	select age_range, channel, count(*) as ch
	from ts.mkt_data md 
	where clicked = 1
	group by channel, age_range
	) c 
left join 
	(
	select age_range, count(*)as tt
	from ts.mkt_data md 
	where clicked = 1
	group by age_range
	) t
on c.age_range = t.age_range
order by  c.age_range, channel
# the age range of target customer is 31-45 because they send more money to send email and SMS for this age range
# In 4 age range, SMS acquire 55% of total and Email acquire 45% of total
# when check the percentage of clicked channel distributed by age_range, there are some notices
# + Only 31-45 clicked email more than SMS but the difference is not significant
# + While, the remaining clicked SMS more with 63-70%


# check age, last_step

select a.age_range, step_order
	, round((a.no/b.no)*100, 2) as percent
	, round((round((a.no/b.no)*100, 2)*100
	/
	lag(round((a.no / b.no) * 100, 2), 1) over (partition by a.age_range order by step_order)),1) as '%change'
from
	(
	select age_range, step_order, count(*) as no
	from ts.mkt_data md 
	where clicked = 1
	group by step_order, age_range
	)a
left join
	(
	select age_range, count(*) as no
	from ts.mkt_data md 
	where clicked = 1
	group by age_range
	)b on a.age_range = b.age_range

# the percentage of purchased of 46-60 is the highest (12.6%) while targeted customer ~ 9-11% (when clicked = 1)
# The bounced rate and saw review is around 30-40%, considered a good bounced rate for ecommerce, according to Capturly.com
# Based on % change of last_step, 60+ age drop dramatically, so at the first stage, this is not customer segment to forcus on
# Purchased step of the remaining is high, now let's check the value of purchase step
	
# Check # product sold, order value, #coupon and total coupon value
select age_range, channel 
	, sum(nb_units) as unit, sum(order_value) as Order_value 
	, 18*(sum(nb_units))
	, count(coupon) as No_Coupon
	, count(coupon)*coupon as Coupon_value
from ts.mkt_data md 
where last_step = 'purchased'
group by age_range, channel  
order by age_range 
# 18-30 and 31-45 are 2 age-range groups bringing the high value for company
# 46-60 brings a half of order value compared to above range (based on the no of customer in each age_range)


 # check which coupon value is the most use?
select sum(value) as coupon_value # total cost for coupon = 6030
from
(select age_range , coupon , count(coupon) as no, (coupon * count(coupon)) as value 
from ts.mkt_data md 
where last_step = 'purchased'
group by age_range , coupon)a
# 46-60 used the highest value of coupon
# the majority of 31-45 used coupon with value = 2 (462 ~ value = 924)
# there is nearly 2 times 2-value coupon used by 18-30 but the highest total value of coupon lies in value 4


# total cost to send SMS, email last campaign = 18412.23
select sum(Sending_Cost)
from
	(
	select age_range, channel, count(age_range) as No, round(count(age_range)*channel_cost,2) as Sending_Cost
	from ts.mkt_data md
	group by channel, age_range
	)a
# total budget for online campaign (not include production cost = 56430)
# the budget of next campaign is 2.4 times to the last one


# in this case, i do not include prodocution cost in profit
# Allocate #sending channel as profit rate to increase awareness (Last step = receive + bounce)

# create profit_percent
drop temporary table profit_percent

create temporary table profit_percent
select * from
	(
	select age_range , channel
		, round((sum(order_value) -  count(channel)*channel_cost - 18*sum(nb_units)),1) as operation_profit #59317
		, round((sum(order_value) -  count(channel)*channel_cost - 18*sum(nb_units))/59317.3,2) as profit_percent
	from ts.mkt_data
	#where last_step = 'purchased'
	group by age_range , channel
	)a

# create channel_sending_No
drop temporary table channel_sending_no

create temporary table channel_sending_no
select * from
	(select age_range, channel, sending_percent*potential as No_sending
	from 
	(
	select c.age_range, channel, round((c.ch / t.tt), 2) AS sending_percent
		, case when c.age_range = '18-30' then 300000
			when c.age_range = '31-45' then 350000
			when c.age_range = '46 - 60' then 500000
			else 200000
		end as 'potential'
	from 
		(
		select age_range, channel, count(*) as ch
		from ts.mkt_data md 
		where clicked = 1
		group by channel, age_range
		) c 
	left join 
		(
		select age_range, count(*)as tt
		from ts.mkt_data md 
		where clicked = 1
		group by age_range
		) t
	on c.age_range = t.age_range
	)a)a

# create next_sending
drop temporary table Next_sending

create temporary table Next_sending
select *from
(
	select a.age_range , a.channel
			, count(a.channel) as lastcamp_no
			, round(No_sending*profit_percent,0) as next_no
			, round(count(a.channel) + No_sending*profit_percent,0) as Next_sending_no_total
			, (count(a.channel)*channel_cost + (round(profit_percent*channel_cost*No_sending,0))) as next_sending_cost
	from ts.mkt_data as a
	join profit_percent as b on a.age_range = b.age_range and a.channel  = b.channel
	join channel_sending_no as c on a.age_range = c.age_range and a.channel = b.channel 
									and b.age_range = c.age_range and c.channel = b.channel 
	group by age_range , channel
	order by age_range 
)a
# gửi lại tất cả pool last campaign + potential * profit_percent -> check cost = 28707 

# create percent_last_step
drop temporary table percent_last_step

create temporary table percent_last_step
select * from
(
select a.age_range, step_order, a.channel, a.coupon
	, (a.no/b.no) as percent
	, round((round((a.no/b.no), 2)
	/
	lag(round((a.no / b.no), 2), 1) over (partition by a.age_range, a.channel, a.coupon order by step_order)),1) as 'percent_change'
from
	(
	select age_range, step_order, channel, count(*) as no, coupon
	from ts.mkt_data md 
	group by step_order, age_range, channel, coupon
	)a
left join
	(
	select age_range, channel, coupon, count(*) as no
	from ts.mkt_data md 
	group by age_range, channel, coupon
	)b on a.age_range = b.age_range and a.channel = b.channel and a.coupon = b.coupon
where step_order =5
)a

select sum(coupon_value)
from
	(
	select a.age_range, a.channel, coupon, percent*100, round(coupon*percent*next_sending_no_total,0)*0.9 as coupon_value
	from percent_last_step as a
	left join next_sending as b on a.age_range = b.age_range and a.channel = b.channel
	where step_order =5
	order by a.channel, a.age_range, coupon
	)a

	
-- check No of each last step
select age_range , channel , last_step , count(*) 
from ts.mkt_data md 
group by age_range , channel , last_step
order by channel , age_range , step_order 

























