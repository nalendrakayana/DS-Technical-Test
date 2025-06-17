-- CREATE TABLE IF NOT EXISTS e_commerce_transaction(
-- 	order_id BIGINT,
-- 	customer_id BIGINT,
-- 	order_date TIMESTAMP,
-- 	payment_value NUMERIC,
-- 	decoy_flag CHAR(1),
-- 	decoy_noise NUMERIC
-- );

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

SELECT 
	decoy_flag,
	COUNT(*) AS total_transaksi,
	AVG(decoy_noise) AS rata_rata_noise,
	STDDEV(decoy_noise) AS std_deviasi_noise,
	MIN(decoy_noise) AS min_noise,
	MAX(decoy_noise) AS max_noise
FROM
	e_commerce_transaction
GROUP BY decoy_flag
ORDER BY decoy_flag;

-- Deteksi anomali
WITH stats_flag AS(
	SELECT
		decoy_flag,
		AVG(decoy_noise) AS avg_noise,
		STDDEV(decoy_noise) AS std_noise
	FROM e_commerce_transaction
	GROUP BY decoy_flag
),
z_scores AS (
	SELECT
		t.order_id,
		t.customer_id,
		t.decoy_flag,
		t.decoy_noise,
		(t.decoy_noise - s.avg_noise) / s.std_noise AS z_score
	FROM 
		e_commerce_transaction AS t
	JOIN stats_flag AS s
		ON t.decoy_flag = s.decoy_flag
)
SELECT
	order_id,
	customer_id,
	decoy_flag,
	decoy_noise,
	z_score
FROM z_scores
WHERE
	ABS(z_score) > 3
ORDER BY 
	ABS(z_score) DESC
LIMIT 5;


-- Mencari repeat-purchase bulanan, dari seluruh customer yang 
-- belanja di bulan X, berapa persen yang pernah belanja di bulan bulan sebelumnya

WITH monthly_customers AS (
	SELECT 
 		DISTINCT DATE_TRUNC('month', order_date)::DATE AS order_month,
		customer_id
 	FROM e_commerce_transaction
),
customer_cohort AS (
	SELECT
		customer_id,
		MIN(order_month) AS cohort_month
	FROM monthly_customers
	GROUP BY customer_id
),
monthly_customer_types AS (
	SELECT
		m.order_month,
		m.customer_id,
		CASE 
			WHEN m.order_month = c.cohort_month THEN 'New'
			ELSE 'Repeat'
		END AS customer_type
	FROM monthly_customers AS m
	JOIN customer_cohort AS c
		ON m.customer_id = c.customer_id
)

SELECT 
	TO_CHAR(order_month, 'YYYY-MM') AS month,
	COUNT(DISTINCT customer_id) AS total_customers,
	COUNT(DISTINCT CASE WHEN customer_type = 'Repeat' THEN customer_id END) AS repeat_customers,
	COUNT(DISTINCT CASE WHEN customer_type = 'New' THEN customer_id END) AS new_customers,
	COUNT(DISTINCT CASE WHEN customer_type = 'Repeat' THEN customer_id END)::NUMERIC * 100 / COUNT(DISTINCT customer_id)::NUMERIC AS repeat_purchase_rate
FROM monthly_customer_types
GROUP BY order_month
ORDER BY order_month
-- Dari query di atas hasil analisi menunjukkan bahwa adanya masalah bisnis pada retensi pelanggan.
-- Bisa dilhat dari waktu ke waktu pelanggan mulai pergi secara masif dari waktu ke waktu
-- Meskipun tingkat repeat_purchase_rate terlihat bagus, namun hasilnya dapat menipu karena 
-- bisa dilihat dari penurunan pelanggan, tingginya angka ini juga karena pelanggan yang semakin sedikit