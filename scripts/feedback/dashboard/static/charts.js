/**
 * 피드백 대시보드 차트 설정
 * Chart.js 기반 시각화
 */

// Chart.js 기본 설정
Chart.defaults.color = '#94a3b8';
Chart.defaults.borderColor = '#334155';
Chart.defaults.font.family = '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif';

// 차트 인스턴스 저장
let timeSeriesChart = null;
let decisionTypeChart = null;
let priorityChart = null;

/**
 * 시계열 차트 (일별 메트릭)
 */
function createTimeSeriesChart(ctx) {
    return new Chart(ctx, {
        type: 'line',
        data: {
            labels: [],
            datasets: [
                {
                    label: '의사결정 수',
                    data: [],
                    borderColor: '#6366f1',
                    backgroundColor: 'rgba(99, 102, 241, 0.1)',
                    fill: true,
                    tension: 0.4,
                    pointRadius: 4,
                    pointHoverRadius: 6
                },
                {
                    label: '성공 수',
                    data: [],
                    borderColor: '#10b981',
                    backgroundColor: 'rgba(16, 185, 129, 0.1)',
                    fill: true,
                    tension: 0.4,
                    pointRadius: 4,
                    pointHoverRadius: 6
                },
                {
                    label: '에러 수',
                    data: [],
                    borderColor: '#ef4444',
                    backgroundColor: 'rgba(239, 68, 68, 0.1)',
                    fill: false,
                    tension: 0.4,
                    pointRadius: 4,
                    pointHoverRadius: 6
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: {
                mode: 'index',
                intersect: false
            },
            plugins: {
                legend: {
                    position: 'top',
                    labels: {
                        usePointStyle: true,
                        padding: 20
                    }
                },
                tooltip: {
                    backgroundColor: '#1e293b',
                    titleColor: '#f1f5f9',
                    bodyColor: '#94a3b8',
                    borderColor: '#334155',
                    borderWidth: 1,
                    padding: 12,
                    displayColors: true
                }
            },
            scales: {
                x: {
                    grid: {
                        display: false
                    },
                    ticks: {
                        maxTicksLimit: 10
                    }
                },
                y: {
                    beginAtZero: true,
                    grid: {
                        color: '#334155'
                    },
                    ticks: {
                        precision: 0
                    }
                }
            }
        }
    });
}

/**
 * 의사결정 유형 도넛 차트
 */
function createDecisionTypeChart(ctx) {
    return new Chart(ctx, {
        type: 'doughnut',
        data: {
            labels: ['전략적', '운영적', '기술적', '긴급', '일반'],
            datasets: [{
                data: [0, 0, 0, 0, 0],
                backgroundColor: [
                    '#6366f1', // primary
                    '#10b981', // success
                    '#3b82f6', // info
                    '#ef4444', // error
                    '#94a3b8'  // gray
                ],
                borderWidth: 0,
                hoverOffset: 8
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            cutout: '65%',
            plugins: {
                legend: {
                    position: 'right',
                    labels: {
                        usePointStyle: true,
                        padding: 15,
                        font: {
                            size: 12
                        }
                    }
                },
                tooltip: {
                    backgroundColor: '#1e293b',
                    titleColor: '#f1f5f9',
                    bodyColor: '#94a3b8',
                    borderColor: '#334155',
                    borderWidth: 1,
                    padding: 12,
                    callbacks: {
                        label: function(context) {
                            const total = context.dataset.data.reduce((a, b) => a + b, 0);
                            const percentage = total > 0 ? ((context.raw / total) * 100).toFixed(1) : 0;
                            return `${context.label}: ${context.raw} (${percentage}%)`;
                        }
                    }
                }
            }
        }
    });
}

/**
 * 우선순위 바 차트
 */
function createPriorityChart(ctx) {
    return new Chart(ctx, {
        type: 'bar',
        data: {
            labels: [],
            datasets: [{
                label: '우선순위 점수',
                data: [],
                backgroundColor: 'rgba(99, 102, 241, 0.8)',
                borderColor: '#6366f1',
                borderWidth: 1,
                borderRadius: 4,
                barThickness: 24
            }]
        },
        options: {
            indexAxis: 'y',
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    display: false
                },
                tooltip: {
                    backgroundColor: '#1e293b',
                    titleColor: '#f1f5f9',
                    bodyColor: '#94a3b8',
                    borderColor: '#334155',
                    borderWidth: 1,
                    padding: 12
                }
            },
            scales: {
                x: {
                    beginAtZero: true,
                    max: 100,
                    grid: {
                        color: '#334155'
                    },
                    ticks: {
                        callback: function(value) {
                            return value + '%';
                        }
                    }
                },
                y: {
                    grid: {
                        display: false
                    },
                    ticks: {
                        callback: function(value, index) {
                            const label = this.getLabelForValue(value);
                            // 긴 라벨 줄이기
                            return label.length > 20 ? label.substring(0, 17) + '...' : label;
                        }
                    }
                }
            }
        }
    });
}

/**
 * 차트 데이터 업데이트 함수들
 */
function updateTimeSeriesChart(chart, data) {
    if (!chart || !data) return;
    
    chart.data.labels = data.labels || [];
    chart.data.datasets[0].data = data.decisions || [];
    chart.data.datasets[1].data = data.successes || [];
    chart.data.datasets[2].data = data.errors || [];
    chart.update('none');
}

function updateDecisionTypeChart(chart, data) {
    if (!chart || !data) return;
    
    const typeMap = {
        'strategic': 0,
        'operational': 1,
        'technical': 2,
        'urgent': 3,
        'general': 4
    };
    
    // 데이터 초기화
    const values = [0, 0, 0, 0, 0];
    
    // 타입별 카운트
    if (data.types) {
        data.types.forEach(item => {
            const idx = typeMap[item.type];
            if (idx !== undefined) {
                values[idx] = item.count;
            }
        });
    }
    
    chart.data.datasets[0].data = values;
    chart.update('none');
}

function updatePriorityChart(chart, data) {
    if (!chart || !data) return;
    
    chart.data.labels = data.items?.map(i => i.title) || [];
    chart.data.datasets[0].data = data.items?.map(i => i.score) || [];
    
    // 점수에 따른 색상 조정
    const colors = (data.items || []).map(item => {
        if (item.score >= 70) return 'rgba(239, 68, 68, 0.8)'; // 높음 - 빨강
        if (item.score >= 40) return 'rgba(245, 158, 11, 0.8)'; // 중간 - 노랑
        return 'rgba(99, 102, 241, 0.8)'; // 낮음 - 파랑
    });
    
    chart.data.datasets[0].backgroundColor = colors;
    chart.update('none');
}

/**
 * 차트 초기화
 */
function initCharts() {
    const timeSeriesCtx = document.getElementById('timeSeriesChart');
    const decisionTypeCtx = document.getElementById('decisionTypeChart');
    const priorityCtx = document.getElementById('priorityChart');
    
    if (timeSeriesCtx) {
        timeSeriesChart = createTimeSeriesChart(timeSeriesCtx.getContext('2d'));
    }
    
    if (decisionTypeCtx) {
        decisionTypeChart = createDecisionTypeChart(decisionTypeCtx.getContext('2d'));
    }
    
    if (priorityCtx) {
        priorityChart = createPriorityChart(priorityCtx.getContext('2d'));
    }
    
    return {
        timeSeries: timeSeriesChart,
        decisionType: decisionTypeChart,
        priority: priorityChart
    };
}

/**
 * 모든 차트 가져오기
 */
function getCharts() {
    return {
        timeSeries: timeSeriesChart,
        decisionType: decisionTypeChart,
        priority: priorityChart
    };
}

// 전역으로 노출
window.ChartConfig = {
    initCharts,
    getCharts,
    updateTimeSeriesChart,
    updateDecisionTypeChart,
    updatePriorityChart
};
