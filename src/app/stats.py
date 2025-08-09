from collections import defaultdict
from datetime import datetime
import threading

_lock = threading.Lock()

class StatsCollector:
    def __init__(self):
        # Przechowujemy dane: {endpoint: {method: count}}
        self.data = defaultdict(lambda: defaultdict(int))
        # Możemy też przechowywać szczegóły logów (opcjonalnie)
        self.logs = []

    def log_request(self, endpoint, method, status_code):
        with _lock:
            self.data[endpoint][method] += 1
            self.logs.append({
                "endpoint": endpoint,
                "method": method,
                "status_code": status_code,
                "timestamp": datetime.utcnow()
            })

    def get_summary(self):
        with _lock:
            return dict(self.data)

    def get_logs(self):
        with _lock:
            return list(self.logs)


stats_collector = StatsCollector()
