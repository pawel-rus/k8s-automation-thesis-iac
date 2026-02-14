import time
import logging
from flask import Blueprint, render_template, request, Response, redirect, url_for, jsonify
from prometheus_client import Counter, Histogram, generate_latest, Gauge

werkzeug_logger = logging.getLogger('werkzeug')
werkzeug_logger.setLevel(logging.ERROR)

class CustomFormatter(logging.Formatter):
    """
    Custom logging formatter to include request details.
    """
    def format(self, record):
        record.ip = getattr(record, 'ip', '-')
        record.method = getattr(record, 'method', '-')
        record.path = getattr(record, 'path', '-')
        record.status_code = getattr(record, 'status_code', '-')
        return super().format(record)

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

log_format = 'time="%(asctime)s" level=%(levelname)s ip=%(ip)s method=%(method)s path=%(path)s status=%(status_code)s - %(message)s'
formatter = CustomFormatter(log_format)

handler = logging.StreamHandler()
handler.setFormatter(formatter)

if logger.hasHandlers():
    logger.handlers.clear()
logger.addHandler(handler)

logger.propagate = False

REQUESTS_TOTAL = Counter('flask_app_requests_total', 'Total HTTP Requests', ['method', 'path', 'http_status'])
REQUEST_LATENCY = Histogram('flask_app_request_latency_seconds', 'HTTP Request Latency in seconds', ['method', 'path'])
ACTIVE_REQUESTS = Gauge('flask_app_active_requests', 'Number of active requests currently being processed', ['method', 'path'])
LOGIN_ATTEMPTS_TOTAL = Counter('flask_app_login_attempts_total', 'Total login attempts', ['status'])

main_bp = Blueprint('main', __name__)

@main_bp.before_request
def before_request_handler():
    request.start_time = time.time()
    ACTIVE_REQUESTS.labels(request.method, request.path).inc()
    logger.debug("--> Request started", extra={'ip': request.remote_addr, 'method': request.method, 'path': request.path, 'status_code': '-'})


@main_bp.after_request
def after_request_handler(response):
    if request.path == '/healthz':
        return response
    ACTIVE_REQUESTS.labels(request.method, request.path).dec()
    latency = time.time() - request.start_time
    REQUEST_LATENCY.labels(request.method, request.path).observe(latency)
    REQUESTS_TOTAL.labels(request.method, request.path, response.status_code).inc()
    
    extra_info = {
        'ip': request.remote_addr,
        'method': request.method,
        'path': request.path,
        'status_code': response.status_code
    }
    logger.info(f"Request processed in {latency:.4f}s", extra=extra_info)
    return response

@main_bp.route('/healthz')
def healthz():
    """
    Health check endpoint.
    """
    return jsonify(status="ok"), 200

@main_bp.route('/')
def index():
    return render_template('index.html', title='Home Page')

@main_bp.route('/about')
def about():
    return render_template('about.html', title='About Us')

@main_bp.route('/contact', methods=['GET', 'POST'])
def contact():
    if request.method == 'POST':
        email = request.form.get('email')
        
        extra_info = {
            'ip': request.remote_addr,
            'method': request.method,
            'path': request.path,
            'status_code': 201
        }
        logger.info(f"Contact form submitted by '{email}'", extra=extra_info)
        return render_template('contact_success.html', title='Thank You')

    return render_template('contact.html', title='Contact')

@main_bp.route('/login', methods=['GET', 'POST'])
def login():
    error = None
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        if username == 'admin' and password == 'password':
            LOGIN_ATTEMPTS_TOTAL.labels(status='success').inc()
            return redirect(url_for('main.dashboard'))
        else:
            LOGIN_ATTEMPTS_TOTAL.labels(status='failed').inc()
            error = 'Invalid username or password.'

    return render_template('login.html', title='Login', error=error)


@main_bp.route('/dashboard')
def dashboard():
    return render_template('dashboard.html', title='Dashboard')

@main_bp.route('/metrics')
def metrics():
    return Response(generate_latest(), mimetype='text/plain')