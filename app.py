import time
import random
import logging
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.metrics import get_meter_provider, set_meter_provider
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter as OTLPSpanExporterGRPC
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter as OTLPMetricExporterGRPC
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter as OTLPSpanExporterHTTP
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter as OTLPMetricExporterHTTP
from opentelemetry.trace import get_tracer_provider, set_tracer_provider

# Configure Trace Provider
# The TracerProvider will automatically use the OTEL_SERVICE_NAME environment variable.
trace.set_tracer_provider(TracerProvider())
tracer_provider = trace.get_tracer_provider()

# gRPC Exporter for Traces
grpc_span_exporter = OTLPSpanExporterGRPC(insecure=True)
grpc_span_processor = BatchSpanProcessor(grpc_span_exporter)
tracer_provider.add_span_processor(grpc_span_processor)

# HTTP Exporter for Traces
http_span_exporter = OTLPSpanExporterHTTP()
http_span_processor = BatchSpanProcessor(http_span_exporter)
tracer_provider.add_span_processor(http_span_processor)

tracer = tracer_provider.get_tracer(__name__)

# Configure Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configure Meter Provider
# gRPC Exporter for Metrics
grpc_metric_exporter = OTLPMetricExporterGRPC(insecure=True)
grpc_reader = PeriodicExportingMetricReader(grpc_metric_exporter)

# HTTP Exporter for Metrics
http_metric_exporter = OTLPMetricExporterHTTP()
http_reader = PeriodicExportingMetricReader(http_metric_exporter)

# The MeterProvider will automatically use the OTEL_SERVICE_NAME environment variable.
meter_provider = MeterProvider(metric_readers=[grpc_reader, http_reader])
set_meter_provider(meter_provider)
meter = get_meter_provider().get_meter(__name__)

# Create a counter metric
request_counter = meter.create_counter(
    "requests",
    description="Number of requests",
    unit="1",
)

# Create a histogram metric
request_latency = meter.create_histogram(
    "request_latency",
    description="Request latency",
    unit="ms",
)

def process_request():
    with tracer.start_as_current_span("process_request") as span:
        # Simulate some work
        latency = random.uniform(50, 500)
        time.sleep(latency / 1000)

        # Record metrics
        request_counter.add(1, {"endpoint": "/api/data"})
        request_latency.record(latency, {"endpoint": "/api/data"})

        span.set_attribute("http.method", "GET")
        span.set_attribute("http.status_code", 200)
        logger.info(f"Request processed with latency: {latency:.2f}ms")
        logger.debug(f"Trace ID: {span.get_span_context().trace_id}")


if __name__ == "__main__":
    logger.info("Starting application...")
    try:
        while True:
            process_request()
            time.sleep(random.uniform(1, 5))
    except KeyboardInterrupt:
        logger.info("Stopping application...")
