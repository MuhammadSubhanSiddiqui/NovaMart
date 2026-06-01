import time

from locust import User, between, events, task
import psycopg2
from psycopg2 import pool


DB_DSN = "dbname=novamart user=novamart_app password=nova_local_dev_key host=localhost"


try:
    db_pool = pool.ThreadedConnectionPool(1, 100, dsn=DB_DSN)
except Exception as exc:
    raise RuntimeError(f"Failed to initialize database pool: {exc}") from exc


class PostgresClient:
    """Custom client to track database query times inside Locust."""

    def execute(self, name, query, params=None):
        start_time = time.perf_counter()
        conn = None
        try:
            conn = db_pool.getconn()
            with conn.cursor() as cursor:
                cursor.execute(query, params)
            conn.commit()

            total_time = int((time.perf_counter() - start_time) * 1000)
            events.request.fire(
                request_type="PostgreSQL",
                name=name,
                response_time=total_time,
                response_length=0,
            )
        except Exception as exc:
            total_time = int((time.perf_counter() - start_time) * 1000)
            if conn is not None:
                conn.rollback()
            events.request.fire(
                request_type="PostgreSQL",
                name=name,
                response_time=total_time,
                response_length=0,
                exception=exc,
            )
            raise
        finally:
            if conn is not None:
                db_pool.putconn(conn)


class NovaMartDatabaseUser(User):
    wait_time = between(1, 3)

    def on_start(self):
        self.client = PostgresClient()

    @task(10)
    def product_search(self):
        query = """
            SELECT p.product_id, p.description_jsonb, r.avg_rating
            FROM products p
            LEFT JOIN mv_product_ratings r ON p.product_id = r.product_id
            WHERE p.description_jsonb @> '{"raw_text": "laptop"}'::jsonb
            LIMIT 50;
        """
        self.client.execute("Product Search", query)

    @task(4)
    def checkout_flow(self):
        query = """
            UPDATE inventory
            SET stock = stock - 1
            WHERE store_id = 1
              AND product_id = 100
              AND stock >= 1;
        """
        self.client.execute("Checkout Inventory Decrement", query)

    @task(3)
    def order_tracking(self):
        query = """
            SELECT o.order_id, o.status, oi.product_id, oi.qty
            FROM orders o
            JOIN orderitems oi ON o.order_id = oi.order_id
            WHERE o.customer_id = 12345;
        """
        self.client.execute("Order Tracking", query)

    @task(2)
    def novapay_creation(self):
        query = """
            UPDATE customers
            SET available_credit = available_credit - 5000,
                version = version + 1
            WHERE customer_id = 12345
              AND version = 1
            RETURNING available_credit;
        """
        self.client.execute("NovaPay Credit Deduction", query)

    @task(1)
    def fraud_detection(self):
        query = """
            SELECT customer_id, COUNT(order_id)
            FROM orders
            GROUP BY customer_id
            HAVING COUNT(order_id) > 5;
        """
        self.client.execute("Fraud Detection Graph", query)