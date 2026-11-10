# World Bank Data Warehouse

An ETL project that integrates **two World Bank API endpoints** (country metadata and four development indicators) for 10 countries from 2010 to 2023. The data goes through a **staging layer**, **quality checks**, and a **star schema** in SQLite, then gets analysed with SQL.

## What I wanted to learn
- How to collect data from an API
- How to clean data and check its quality
- How to organise data into tables that are easy to analyse (a star schema)
- How to write SQL queries on that data

## What the project does
1. Gets country details and four indicators (GDP per capita, population, life expectancy, internet use) for 10 countries from 2010 to 2023.
2. Cleans the data and checks for duplicates, missing values and impossible numbers.
3. Stores the data in a SQLite database using one fact table and three dimension tables.
4. Runs 11 SQL queries to answer questions about the data.

## Questions I answered
- Which countries grew their GDP per capita the most since 2010?
- How does life expectancy compare across countries?
- How fast did internet use grow in each country?

## A few results
- China had the biggest GDP per capita growth between 2010 and 2023 (about 180%).
- Japan had the highest life expectancy in 2023 (84 years) and Nigeria the lowest (54.5).
- Indonesia had the biggest rise in internet use (about 58 percentage points).

## Tools
Python, Pandas, SQLite, SQL

## How to run
pip install -r requirements.txt
python src/pipeline.py
python src/run_queries.py

## Files
- src/pipeline.py: collects, cleans and loads the data
- src/run_queries.py: runs the SQL queries
- sql/schema.sql: creates the tables
- sql/queries.sql: the analysis queries

## What I'd like to improve
- Add more countries and indicators
- Schedule the pipeline to run automatically
- Try PySpark for larger data

## Data source
World Bank Open Data (data.worldbank.org), CC BY 4.0