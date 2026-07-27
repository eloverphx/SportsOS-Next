process.env.NODE_ENV = "test";
process.env.HOST = "127.0.0.1";
process.env.PORT = "4001";
process.env.DASHBOARD_ORIGIN = "http://localhost:4000";
process.env.PUBLIC_API_URL = "http://localhost:4001";

process.env.MYSQL_HOST = "localhost";
process.env.MYSQL_PORT = "3306";
process.env.MYSQL_DATABASE = "sportsos_test";
process.env.MYSQL_USER = "sportsos";
process.env.MYSQL_PASSWORD = "test-password";

process.env.JWT_SECRET = "sportsos-test-jwt-secret-that-is-at-least-32-characters";

process.env.REDIS_URL = "redis://localhost:6379";
process.env.MQTT_URL = "mqtt://localhost:1883";

process.env.MINIO_ENDPOINT = "localhost";
process.env.MINIO_PORT = "9000";
process.env.MINIO_ACCESS_KEY = "test-access-key";
process.env.MINIO_SECRET_KEY = "test-secret-key";
process.env.MINIO_BUCKET = "sportsos-test";
