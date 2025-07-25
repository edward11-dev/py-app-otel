import time
import random
import logging
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import ConsoleSpanExporter, SimpleSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import ConsoleMetricExporter, PeriodicExportingMetricReader
from opentelemetry.metrics import get_meter_provider, set_meter_provider
from opentelemetry.trace import get_tracer_provider, set_tracer_provider

# Configure Trace Provider
trace.set_tracer_provider(TracerProvider())
tracer_provider = trace.get_tracer_provider()
span_processor = SimpleSpanProcessor(ConsoleSpanExporter())
tracer_provider.add_span_processor(span_processor)
tracer = tracer_provider.get_tracer(__name__)

# Configure Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configure Meter Provider
reader = PeriodicExportingMetricReader(ConsoleMetricExporter())
meter_provider = MeterProvider(metric_readers=[reader])
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
