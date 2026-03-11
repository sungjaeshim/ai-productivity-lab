/**
 * Feedback Dashboard Client
 * Phase 4 Task T-015
 */

class Dashboard {
    constructor() {
        this.ws = null;
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 5;
        
        this.init();
    }
    
    init() {
        this.connectWebSocket();
        this.loadInitialData();
        this.setupTabs();
    }
    
    // WebSocket Connection
    connectWebSocket() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${protocol}//${window.location.host}/ws/realtime`;
        
        this.ws = new WebSocket(wsUrl);
        
        this.ws.onopen = () => {
            console.log('WebSocket connected');
            this.updateConnectionStatus(true);
            this.reconnectAttempts = 0;
            
            // Subscribe to all channels
            this.ws.send(JSON.stringify({
                type: 'subscribe',
                channels: ['metrics', 'experiments', 'priorities']
            }));
        };
        
        this.ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            this.handleWebSocketMessage(data);
        };
        
        this.ws.onclose = () => {
            console.log('WebSocket disconnected');
            this.updateConnectionStatus(false);
            this.attemptReconnect();
        };
        
        this.ws.onerror = (error) => {
            console.error('WebSocket error:', error);
        };
    }
    
    attemptReconnect() {
        if (this.reconnectAttempts < this.maxReconnectAttempts) {
            this.reconnectAttempts++;
            const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts), 30000);
            console.log(`Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts})`);
            setTimeout(() => this.connectWebSocket(), delay);
        }
    }
    
    updateConnectionStatus(connected) {
        const statusEl = document.getElementById('connection-status');
        const dot = statusEl.querySelector('.status-dot');
        const text = statusEl.querySelector('span:last-child');
        
        if (connected) {
            dot.classList.remove('disconnected');
            dot.classList.add('connected');
            text.textContent = 'Connected';
        } else {
            dot.classList.remove('connected');
            dot.classList.add('disconnected');
            text.textContent = 'Disconnected';
        }
    }
    
    handleWebSocketMessage(data) {
        console.log('WebSocket message:', data.type);
        
        switch (data.type) {
            case 'connected':
                if (data.data) {
                    this.updateMetrics(data.data.metrics);
                    this.updatePriorities(data.data.top_priorities);
                }
                break;
            case 'metrics_update':
                this.updateMetrics(data.data);
                break;
            case 'priority_update':
                this.updatePriorities(data.data);
                break;
            case 'experiment_update':
                this.loadExperiments();
                break;
            case 'pong':
                // Heartbeat response
                break;
        }
        
        this.updateLastUpdate();
    }
    
    // Load Initial Data
    async loadInitialData() {
        try {
            await Promise.all([
                this.loadMetrics(),
                this.loadPriorities(),
                this.loadExperiments(),
                this.loadRecentActivity('decisions')
            ]);
        } catch (error) {
            console.error('Failed to load initial data:', error);
        }
    }
    
    async loadMetrics() {
        try {
            const response = await fetch('/api/metrics/summary');
            const data = await response.json();
            this.updateMetrics(data);
        } catch (error) {
            console.error('Failed to load metrics:', error);
        }
    }
    
    async loadPriorities() {
        try {
            const response = await fetch('/api/priorities?limit=10');
            const data = await response.json();
            this.updatePriorities(data.items);
        } catch (error) {
            console.error('Failed to load priorities:', error);
        }
    }
    
    async loadExperiments() {
        try {
            const [listResponse, statsResponse] = await Promise.all([
                fetch('/api/experiments?status=running&limit=10'),
                fetch('/api/experiments/stats/summary')
            ]);
            
            const listData = await listResponse.json();
            const statsData = await statsResponse.json();
            
            this.updateExperiments(listData.experiments, statsData);
        } catch (error) {
            console.error('Failed to load experiments:', error);
        }
    }
    
    async loadRecentActivity(type) {
        try {
            const response = await fetch(`/api/metrics?days=7`);
            const data = await response.json();
            
            let items = [];
            switch (type) {
                case 'decisions':
                    items = data.recent_decisions || [];
                    break;
                case 'tasks':
                    items = data.recent_tasks || [];
                    break;
                case 'errors':
                    items = data.recent_errors || [];
                    break;
            }
            
            this.updateActivityList(items, type);
        } catch (error) {
            console.error('Failed to load activity:', error);
        }
    }
    
    // Update UI
    updateMetrics(metrics) {
        if (!metrics) return;
        
        // Decisions
        if (metrics.decisions) {
            document.getElementById('decisions-total').textContent = metrics.decisions.total || 0;
            document.getElementById('decisions-today').textContent = metrics.decisions.today || 0;
        }
        
        // Tasks
        if (metrics.tasks) {
            document.getElementById('tasks-completed').textContent = metrics.tasks.completed || 0;
            document.getElementById('tasks-pending').textContent = metrics.tasks.pending || 0;
            
            const progress = metrics.tasks.completion_rate || 0;
            document.getElementById('tasks-progress').style.width = `${progress}%`;
        }
        
        // Errors
        if (metrics.errors) {
            document.getElementById('errors-total').textContent = metrics.errors.total || 0;
            document.getElementById('errors-unresolved').textContent = metrics.errors.unresolved || 0;
        }
        
        // Feedback
        if (metrics.feedback) {
            document.getElementById('feedback-positive').textContent = metrics.feedback.positive || 0;
            document.getElementById('feedback-negative').textContent = metrics.feedback.negative || 0;
        }
    }
    
    updatePriorities(items) {
        const listEl = document.getElementById('priority-list');
        
        if (!items || items.length === 0) {
            listEl.innerHTML = '<li class="loading">No priorities found</li>';
            return;
        }
        
        listEl.innerHTML = items.map(item => `
            <li class="priority-item">
                <span class="priority-score ${item.priority_score > 10 ? 'high' : ''}">${item.priority_score.toFixed(1)}</span>
                <span class="priority-type">${item.item_type}</span>
                <span class="priority-title">${this.escapeHtml(item.title)}</span>
            </li>
        `).join('');
    }
    
    updateExperiments(experiments, stats) {
        // Update stats
        document.getElementById('exp-running').textContent = stats.running || 0;
        document.getElementById('exp-completed').textContent = stats.completed || 0;
        document.getElementById('exp-success-rate').textContent = `${stats.success_rate || 0}%`;
        
        // Update list
        const listEl = document.getElementById('experiment-list');
        
        if (!experiments || experiments.length === 0) {
            listEl.innerHTML = '<li class="loading">No running experiments</li>';
            return;
        }
        
        listEl.innerHTML = experiments.map(exp => `
            <li class="experiment-item">
                <span class="experiment-status ${exp.status}">${exp.status}</span>
                <span class="experiment-name">${this.escapeHtml(exp.name)}</span>
            </li>
        `).join('');
    }
    
    updateActivityList(items, type) {
        const listEl = document.getElementById('activity-list');
        
        if (!items || items.length === 0) {
            listEl.innerHTML = '<li class="loading">No recent activity</li>';
            return;
        }
        
        listEl.innerHTML = items.map(item => {
            let content = '';
            let time = item.created_at || '';
            
            switch (type) {
                case 'decisions':
                    content = `[${item.decision_type || 'decision'}] ${item.outcome || ''}`;
                    break;
                case 'tasks':
                    content = `${item.title} (${item.status})`;
                    break;
                case 'errors':
                    content = `[${item.severity}] ${item.message}`;
                    break;
            }
            
            return `<li class="activity-item">${this.escapeHtml(content)}<span class="activity-time">${time}</span></li>`;
        }).join('');
    }
    
    updateLastUpdate() {
        const now = new Date();
        document.getElementById('last-update').textContent = now.toLocaleTimeString();
    }
    
    // Setup Tabs
    setupTabs() {
        const tabs = document.querySelectorAll('.tab');
        
        tabs.forEach(tab => {
            tab.addEventListener('click', () => {
                tabs.forEach(t => t.classList.remove('active'));
                tab.classList.add('active');
                
                const type = tab.dataset.tab;
                this.loadRecentActivity(type);
            });
        });
    }
    
    // Utility
    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text || '';
        return div.innerHTML;
    }
}

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    window.dashboard = new Dashboard();
});
