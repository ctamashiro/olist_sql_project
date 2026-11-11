-- 01_setup.sql: warehouse, database, schemas, file format, stage
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS olist_wh
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60          -- shuts off after 60s idle so you don't burn credits
  AUTO_RESUME = TRUE;

CREATE DATABASE IF NOT EXISTS olist;
CREATE SCHEMA IF NOT EXISTS olist.raw;        -- untouched CSV data
CREATE SCHEMA IF NOT EXISTS olist.analytics;  -- cleaned star schema (later)

USE WAREHOUSE olist_wh;
USE SCHEMA olist.raw;

CREATE OR REPLACE FILE FORMAT csv_format
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'   -- review text has commas + line breaks
  NULL_IF = ('')
  EMPTY_FIELD_AS_NULL = TRUE;

CREATE OR REPLACE STAGE olist_stage FILE_FORMAT = csv_format;



