import sys

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

try:

    logger.debug("App is starting...")
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

    # Logging setup
    logger.debug("Logging test - Debug message")
    logger.info("Logging test - Info message")
    logger.error("Logging test - Error message")


    # Set up traces
    trace.set_tracer_provider(
        TracerProvider(
            resource=Resource.create({SERVICE_NAME: "my-python-app"})
        )
    )
    tracer = trace.get_tracer(__name__)
    span_processor = BatchSpanProcessor(OTLPSpanExporter(endpoint="http://otel-collector-collector:4318", insecure=True))
    trace.get_tracer_provider().add_span_processor(span_processor)

    logger.info("Tracer configured")

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

    logger.info("Metrics configured")
    # Auto-instrument HTTP requests
    RequestsInstrumentor().instrument()
    logger.info("Instrumentation done")

     # Keep the container alive for testing
    import time
    while True:
        logger.debug("Running app...")
        time.sleep(10)

except Exception as e:
    logging.exception("App failed to start due to error:")
    sys.exit(1)

