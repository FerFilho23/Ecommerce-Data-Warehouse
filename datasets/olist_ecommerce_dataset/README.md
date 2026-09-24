# Olist Brazilian e-commerce dataset

The CSVs in `olist_ecommerce_dataset/` are a **subsampled** version of the public Olist dataset (~500 random rows per table) so the workshop stays under one megabyte and clones quickly.

The full ~110MB dataset lives on Kaggle:
https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

## Tables

| File                                          | Sample rows | Description                                  |
|-----------------------------------------------|-------------|----------------------------------------------|
| `olist_customers_dataset.csv`                 | 500         | Unique customer ids, zip code, city, state   |
| `olist_geolocation_dataset.csv`               | 500         | Zip code -> lat/long/city/state              |
| `olist_order_items_dataset.csv`               | 500         | Each item per order with seller + price      |
| `olist_order_payments_dataset.csv`            | 500         | Payment value, type, installments per order  |
| `olist_orders_dataset.csv`                    | 500         | Orders with status + delivery timestamps     |
| `olist_products_dataset.csv`                  | 500         | Products with category + dimensions          |
| `olist_sellers_dataset.csv`                   | full (~3K)  | Seller ids + zip + city + state              |
| `product_category_name_translation.csv`       | full (~70)  | Portuguese -> English category names         |

## Loading the full dataset

```bash
# Download the Kaggle archive (requires Kaggle credentials)
kaggle datasets download -d olistbr/brazilian-ecommerce -p datasets/olist_ecommerce_dataset/ --unzip

# Or via direct download from your browser, then unzip into datasets/olist_ecommerce_dataset/
```

Then upload to your GCS raw bucket:

```bash
gsutil -m cp datasets/olist_ecommerce_dataset/*.csv gs://${GCS_RAW_BUCKET}/raw/
```

## License

The Olist dataset is published by Olist Store under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).