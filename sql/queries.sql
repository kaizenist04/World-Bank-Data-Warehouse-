-- 1. Latest GDP per capita for each country (ROW_NUMBER)
SELECT name, year_key AS year, ROUND(value, 0) AS gdp_per_capita_usd
FROM (
    SELECT c.name, f.year_key, f.value,
           ROW_NUMBER() OVER (PARTITION BY f.country_key ORDER BY f.year_key DESC) AS rn
    FROM fact_indicator f
    JOIN dim_country c   ON c.country_key = f.country_key
    JOIN dim_indicator i ON i.indicator_key = f.indicator_key
    WHERE i.indicator_code = 'NY.GDP.PCAP.CD'
)
WHERE rn = 1
ORDER BY gdp_per_capita_usd DESC;

-- 2. GDP per capita growth from first to last available year (CTE + self-join)
WITH g AS (
    SELECT c.name, f.year_key, f.value,
           ROW_NUMBER() OVER (PARTITION BY f.country_key ORDER BY f.year_key ASC)  AS rn_first,
           ROW_NUMBER() OVER (PARTITION BY f.country_key ORDER BY f.year_key DESC) AS rn_last
    FROM fact_indicator f
    JOIN dim_country c   ON c.country_key = f.country_key
    JOIN dim_indicator i ON i.indicator_key = f.indicator_key
    WHERE i.indicator_code = 'NY.GDP.PCAP.CD'
)
SELECT a.name,
       a.year_key AS start_year, ROUND(a.value, 0) AS start_gdp,
       b.year_key AS end_year,   ROUND(b.value, 0) AS end_gdp,
       ROUND(100.0 * (b.value - a.value) / a.value, 1) AS growth_pct
FROM g a
JOIN g b ON a.name = b.name
WHERE a.rn_first = 1 AND b.rn_last = 1
ORDER BY growth_pct DESC;

-- 3. Life expectancy ranking in each country's most recent year (RANK)
SELECT name, year, life_expectancy,
       RANK() OVER (ORDER BY life_expectancy DESC) AS rank
FROM (
    SELECT c.name, f.year_key AS year, ROUND(f.value, 1) AS life_expectancy,
           ROW_NUMBER() OVER (PARTITION BY f.country_key ORDER BY f.year_key DESC) AS rn
    FROM fact_indicator f
    JOIN dim_country c   ON c.country_key = f.country_key
    JOIN dim_indicator i ON i.indicator_key = f.indicator_key
    WHERE i.indicator_code = 'SP.DYN.LE00.IN'
)
WHERE rn = 1;

-- 4. Year-over-year change in internet users for India (LAG)
SELECT f.year_key AS year,
       ROUND(f.value, 1) AS internet_users_pct,
       ROUND(f.value - LAG(f.value) OVER (ORDER BY f.year_key), 1) AS change_pts
FROM fact_indicator f
JOIN dim_country c   ON c.country_key = f.country_key
JOIN dim_indicator i ON i.indicator_key = f.indicator_key
WHERE c.iso3 = 'IND' AND i.indicator_code = 'IT.NET.USER.ZS'
ORDER BY f.year_key;

-- 5. Average life expectancy and GDP per capita by region
SELECT c.region,
       ROUND(AVG(CASE WHEN i.indicator_code = 'SP.DYN.LE00.IN' THEN f.value END), 1) AS avg_life_expectancy,
       ROUND(AVG(CASE WHEN i.indicator_code = 'NY.GDP.PCAP.CD' THEN f.value END), 0) AS avg_gdp_per_capita
FROM fact_indicator f
JOIN dim_country c   ON c.country_key = f.country_key
JOIN dim_indicator i ON i.indicator_key = f.indicator_key
GROUP BY c.region
ORDER BY avg_gdp_per_capita DESC;

-- 6. Wide view: all four indicators side by side for one year (pivot with CASE)
SELECT c.name,
       ROUND(MAX(CASE WHEN i.indicator_code = 'NY.GDP.PCAP.CD' THEN f.value END), 0) AS gdp_per_capita,
       ROUND(MAX(CASE WHEN i.indicator_code = 'SP.POP.TOTL'    THEN f.value END) / 1000000.0, 1) AS population_millions,
       ROUND(MAX(CASE WHEN i.indicator_code = 'SP.DYN.LE00.IN' THEN f.value END), 1) AS life_expectancy,
       ROUND(MAX(CASE WHEN i.indicator_code = 'IT.NET.USER.ZS' THEN f.value END), 1) AS internet_pct
FROM fact_indicator f
JOIN dim_country c   ON c.country_key = f.country_key
JOIN dim_indicator i ON i.indicator_key = f.indicator_key
WHERE f.year_key = 2020
GROUP BY c.name
ORDER BY gdp_per_capita DESC;

-- 7. Total population by income level in 2020
SELECT c.income_level,
       COUNT(DISTINCT c.country_key) AS countries,
       ROUND(SUM(f.value) / 1000000.0, 0) AS population_millions
FROM fact_indicator f
JOIN dim_country c   ON c.country_key = f.country_key
JOIN dim_indicator i ON i.indicator_key = f.indicator_key
WHERE i.indicator_code = 'SP.POP.TOTL' AND f.year_key = 2020
GROUP BY c.income_level
ORDER BY population_millions DESC;

-- 8. Fastest growth in internet use between first and last year (CTE)
WITH net AS (
    SELECT c.name, f.year_key, f.value,
           ROW_NUMBER() OVER (PARTITION BY f.country_key ORDER BY f.year_key ASC)  AS rn_first,
           ROW_NUMBER() OVER (PARTITION BY f.country_key ORDER BY f.year_key DESC) AS rn_last
    FROM fact_indicator f
    JOIN dim_country c   ON c.country_key = f.country_key
    JOIN dim_indicator i ON i.indicator_key = f.indicator_key
    WHERE i.indicator_code = 'IT.NET.USER.ZS'
)
SELECT a.name,
       ROUND(a.value, 1) AS start_pct,
       ROUND(b.value, 1) AS end_pct,
       ROUND(b.value - a.value, 1) AS gain_in_points
FROM net a
JOIN net b ON a.name = b.name
WHERE a.rn_first = 1 AND b.rn_last = 1
ORDER BY gain_in_points DESC;

-- 9. 3-year moving average of GDP per capita for India
SELECT f.year_key AS year,
       ROUND(f.value, 0) AS gdp_per_capita,
       ROUND(AVG(f.value) OVER (ORDER BY f.year_key ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS moving_avg_3y
FROM fact_indicator f
JOIN dim_country c   ON c.country_key = f.country_key
JOIN dim_indicator i ON i.indicator_key = f.indicator_key
WHERE c.iso3 = 'IND' AND i.indicator_code = 'NY.GDP.PCAP.CD'
ORDER BY f.year_key;

-- 10. Data completeness: rows per indicator (quality check)
SELECT i.indicator_name,
       COUNT(*) AS rows_loaded,
       COUNT(DISTINCT f.country_key) AS countries,
       MIN(f.year_key) AS first_year,
       MAX(f.year_key) AS last_year
FROM fact_indicator f
JOIN dim_indicator i ON i.indicator_key = f.indicator_key
GROUP BY i.indicator_name;

-- 11. Orphan check: fact rows with no matching country (should return 0 rows)
SELECT f.country_key, COUNT(*) AS orphan_rows
FROM fact_indicator f
LEFT JOIN dim_country c ON c.country_key = f.country_key
WHERE c.country_key IS NULL
GROUP BY f.country_key;
