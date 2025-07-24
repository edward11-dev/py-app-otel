from opentelemetry import trace
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry import metrics as metric
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.instrumentation.requests import RequestsInstrumentor
import logging

logging.basicConfig(level=logging.DEBUG)
logging.debug("Debug message")
logging.info("Info message")
logging.error("Error message")


# Set up traces
trace.set_tracer_provider(
    TracerProvider(
        resource=Resource.create({SERVICE_NAME: "my-python-app"})
    )
)
tracer = trace.get_tracer(__name__)
span_processor = BatchSpanProcessor(OTLPSpanExporter(endpoint="http://otel-collector-collector:4317", insecure=True))
trace.get_tracer_provider().add_span_processor(span_processor)

# Set up metrics
metric.set_meter_provider(
    MeterProvider(
        metric_readers=[
            PeriodicExportingMetricReader(
                OTLPMetricExporter(endpoint="http://otel-collector-collector:4317", insecure=True)
            )
        ]
    )
)

# Auto-instrument HTTP requests
RequestsInstrumentor().instrument()
