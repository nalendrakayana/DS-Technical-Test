-- CREATE TABLE IF NOT EXISTS e_commerce_transaction(
-- 	order_id BIGINT,
-- 	customer_id BIGINT,
-- 	order_date TIMESTAMP,
-- 	payment_value NUMERIC,
-- 	decoy_flag CHAR(1),
-- 	decoy_noise NUMERIC
-- );

-- Doing this task in pgAdmin, that's why there is no syntax to read the csv file

-- Ambil tanggal order terakhir untuk perhitungan recency
SELECT MAX(order_date) AS last_order_date
FROM e_commerce_transaction;

-- Check duplikat order 
SELECT order_id, COUNT(*) AS duplikat_order
FROM e_commerce_transaction
GROUP BY order_id
HAVING COUNT(*) > 1;

-- Bikin RFM dan RFM score untuk segmentasi pelanggan
WITH rfm AS(
	SELECT
		customer_id,
		'2025-05-05'::DATE - MAX(ORDER_DATE)::DATE AS recency,
		COUNT(DISTINCT order_id) AS frequency,
		SUM(payment_value) AS monetary
	FROM e_commerce_transaction
	GROUP BY customer_id
),
rfm_score AS (
	SELECT
		customer_id,
		recency,
		frequency,
		monetary,
		NTILE(4) OVER (ORDER BY recency DESC) AS recency_score,
		NTILE(4) OVER (ORDER BY frequency ASC) AS frequency_score,
		NTILE(4) OVER (ORDER BY monetary ASC) AS monetary_score
	FROM rfm
)

SELECT
	r.customer_id,
	r.recency,
	r.frequency,
	r.monetary,
	r.recency_score,
	r.frequency_score,
	r.monetary_score,
	CASE 
		WHEN r.recency_score = 4 AND r.frequency_score = 4 AND r.monetary_score = 4 THEN 'Sultan'
		WHEN r.recency_score >= 3 AND r.frequency_score >= 3 AND r.monetary_score >= 3 THEN 'Loyal'
		WHEN r.monetary_score = 4 AND r.frequency_score < 3 THEN 'Big spenders'
		WHEN r.recency_score > 2 AND r.frequency_score > 1 AND r.monetary_score > 1 THEN 'Potensial langganan'
		WHEN r.recency_score = 4 AND r.frequency_score = 1 THEN 'Pelanggan baru'
		WHEN r.recency_score < 3 AND r.frequency_score > 2 THEN 'At risk'
		WHEN r.recency_score <= 2 AND r.frequency_score <= 2 AND r.monetary_score <= 2 THEN 'Inactive'
		ELSE 'Others'
	END AS customer_segmentation
FROM rfm_score AS r
ORDER BY r.customer_id