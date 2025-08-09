from flask import Blueprint, render_template, jsonify, request
from .stats import stats_collector

bp = Blueprint('main', __name__)

@bp.route('/health')
def health():
    return jsonify({"status": "ok"}), 200

@bp.route('/')
def index():
    resp = render_template('index.html')
    stats_collector.log_request(endpoint='/', method=request.method, status_code=200)
    return resp

@bp.route('/about')
def about():
    resp = render_template('about.html')
    stats_collector.log_request(endpoint='/about', method=request.method, status_code=200)
    return resp

@bp.route('/contact', methods=['GET', 'POST'])
def contact():
    if request.method == 'POST':
        status_code = 201
        content = "<h2>Dziękujemy za kontakt!</h2>"
        stats_collector.log_request(endpoint='/contact', method='POST', status_code=status_code)
        return content, status_code

    stats_collector.log_request(endpoint='/contact', method='GET', status_code=200)
    return render_template('contact.html')

@bp.route('/stats')
def stats():
    summary = stats_collector.get_summary()
    logs = stats_collector.get_logs()
    return render_template('stats.html', summary=summary, logs=logs)
