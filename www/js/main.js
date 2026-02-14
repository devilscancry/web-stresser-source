﻿let cooldownInterval;

document.addEventListener('DOMContentLoaded', () => {
    const path = window.location.pathname;

    // Page router
    if (path.includes('login.html')) {
        handleLoginPage();
    } else if (path.includes('dashboard.html')) {
        handleDashboardPage();
    } else if (path.includes('attack-hub.html')) {
        handleAttackHubPage();
    } else if (path.includes('ip-lookup.html')) {
        handleIpLookupPage();
    }
});

function getAuthToken() {
    return localStorage.getItem('jwt_token');
}

function displayMessage(message, type = 'error', containerId = 'error-message') {
    const errorDiv = document.getElementById('error-message');
    if (errorDiv) {
        errorDiv.textContent = message;
        errorDiv.className = type === 'error' ? 'error-box' : 'success-box';
        errorDiv.style.display = 'block';
    }
}

function handleLoginPage() {
    const loginForm = document.getElementById('login-form');
    if (loginForm) {
        loginForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const email = document.getElementById('email').value;
            const password = document.getElementById('password').value;

            try {
                const response = await fetch('/api/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ email, password }),
                });

                const data = await response.json();

                if (response.ok) {
                    localStorage.setItem('jwt_token', data.token);
                    if (data.force_password_change) {
                        localStorage.setItem('force_password_change', 'true');
                    }
                    window.location.href = '/dashboard.html';
                } else {
                    displayMessage(data.error || 'Login failed.');
                }
            } catch (error) {
                displayMessage('An error occurred. Please try again.');
            }
        });
    }
}

function startCooldownTimer(seconds) {
    clearInterval(cooldownInterval);
    const timerEl = document.getElementById('cooldown-timer');
    if (!timerEl) return;

    let remaining = seconds;
    
    if (remaining <= 0) {
        timerEl.textContent = 'Ready';
        return;
    }

    timerEl.textContent = `${remaining}s`;
    cooldownInterval = setInterval(() => {
        remaining--;
        if (remaining >= 0) {
            timerEl.textContent = `${remaining}s`;
        } else {
            timerEl.textContent = 'Ready';
            clearInterval(cooldownInterval);
        }
    }, 1000);
}

function handleAuthPageSetup() {
    const token = getAuthToken();
    if (!token) {
        window.location.href = '/login.html';
        return false;
    }

    // Check for forced password change
    if (localStorage.getItem('force_password_change') === 'true') {
        const modal = document.getElementById('password-modal');
        if (modal) {
            modal.style.display = 'flex';
            const form = document.getElementById('change-password-form');
            form.addEventListener('submit', async (e) => {
                e.preventDefault();
                const newPassword = document.getElementById('new-password').value;
                try {
                    const res = await fetch('/api/change-password', {
                        method: 'POST',
                        headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
                        body: JSON.stringify({ new_password: newPassword })
                    });
                    if (res.ok) {
                        localStorage.removeItem('force_password_change');
                        modal.style.display = 'none';
                        alert('Password updated successfully.');
                    } else {
                        alert('Failed to update password.');
                    }
                } catch (err) {
                    console.error(err);
                }
            });
        }
    }

    const logoutBtn = document.getElementById('logout-btn');

    // Sidebar Toggle Logic
    const sidebarToggle = document.getElementById('sidebar-toggle');
    const sidebar = document.getElementById('sidebar');
    if (sidebarToggle && sidebar) {
        sidebarToggle.addEventListener('click', () => {
            sidebar.classList.toggle('active');
        });
    }

    async function fetchDashboardInfo() {
        try {
            const response = await fetch('/api/dashboard/info', { headers });
            if (response.status === 401) {
                localStorage.removeItem('jwt_token');
                window.location.href = '/login.html';
                return;
            }
            const data = await response.json();
            const user = data.user;
            const attacks = data.attacks || [];
            
            const emailEl = document.getElementById('user-email');
            if(emailEl) emailEl.textContent = user.email;
            
            const planName = user.plan_name || 'Unknown';
            document.getElementById('plan-name').innerHTML = `${planName} ${user.is_vip ? '<span class="vip-badge">(VIP)</span>' : ''}`;
            document.getElementById('active-attacks').textContent = attacks.length;
            document.getElementById('max-concurrents').textContent = user.max_concurrents;
            document.getElementById('max-time').textContent = user.max_time;
            
            const durationInput = document.getElementById('duration');
            if(durationInput) durationInput.max = user.max_time;

            // Update sidebar plan badge
            const planBadge = document.getElementById('user-plan-badge');
            if (planBadge) planBadge.textContent = planName;

            // Update Attacks Table
            const attacksList = document.getElementById('attacks-list');
            if (attacksList) {
                if (attacks.length === 0) {
                    attacksList.innerHTML = '<tr><td colspan="3" style="text-align:center; color: var(--text-muted);">No active attacks</td></tr>';
                } else {
                    attacksList.innerHTML = '';
                    const now = new Date();
                    attacks.forEach(attack => {
                        const endTime = new Date(attack.end_time);
                        const remaining = Math.max(0, Math.ceil((endTime - now) / 1000));
                        const row = document.createElement('tr');
                        row.innerHTML = `
                            <td>${attack.target}:${attack.port}</td>
                            <td>${attack.method}</td>
                            <td>${remaining}s</td>
                        `;
                        attacksList.appendChild(row);
                    });
                }
            }

            const cooldownEnd = user.last_attack_time ? new Date(new Date(user.last_attack_time).getTime() + user.cooldown * 1000) : null;
            const now = new Date();
            if (cooldownEnd && cooldownEnd > now) {
                const remaining = Math.ceil((cooldownEnd - now) / 1000);
                startCooldownTimer(remaining);
            } else {
                startCooldownTimer(0);
            }

        } catch (error) {
            console.error('Failed to fetch dashboard info:', error);
        }
    }

    async function fetchMethods() {
        try {
            const response = await fetch('/api/methods', { headers });
            const data = await response.json();
            const methodSelect = document.getElementById('method');
            methodSelect.innerHTML = '<option value="">Select a method</option>';
            for (const method in data) {
                const option = document.createElement('option');
                option.value = method;
                option.textContent = method;
                methodSelect.appendChild(option);
            }
        } catch (error) {
            console.error('Failed to fetch methods:', error);
        }
    }

    if (logoutBtn) {
        logoutBtn.addEventListener('click', () => {
            localStorage.removeItem('jwt_token');
            window.location.href = '/login.html';
        });
    }

    return true;
}

async function fetchDashboardInfo() {
    const headers = { 'Authorization': `Bearer ${getAuthToken()}`, 'Content-Type': 'application/json' };
    try {
        const response = await fetch('/api/dashboard/info', { headers });
        if (response.status === 401) {
            localStorage.removeItem('jwt_token');
            window.location.href = '/login.html';
            return;
        }
        const data = await response.json();
        const user = data.user;
        const attacks = data.attacks || [];
        
        const emailEl = document.getElementById('user-email');
        if(emailEl) emailEl.textContent = user.email;
        
        const planName = user.plan_name || 'Unknown';
        
        // Elements might not exist on all pages, so check for them
        const planNameEl = document.getElementById('plan-name');
        if (planNameEl) planNameEl.innerHTML = `${planName} ${user.is_vip ? '<span class="vip-badge">(VIP)</span>' : ''}`;
        
        const activeAttacksEl = document.getElementById('active-attacks');
        if (activeAttacksEl) activeAttacksEl.textContent = attacks.length;

        const maxConcurrentsEl = document.getElementById('max-concurrents');
        if (maxConcurrentsEl) maxConcurrentsEl.textContent = user.max_concurrents;

        const maxTimeEl = document.getElementById('max-time');
        if (maxTimeEl) maxTimeEl.textContent = user.max_time;
        
        const durationInput = document.getElementById('duration');
        if(durationInput) durationInput.max = user.max_time;

        // Update sidebar plan badge
        const planBadge = document.getElementById('user-plan-badge');
        if (planBadge) planBadge.textContent = planName;

        // Update Attacks Table
        const attacksList = document.getElementById('attacks-list');
        if (attacksList) {
            if (attacks.length === 0) {
                attacksList.innerHTML = '<tr><td colspan="3" style="text-align:center; color: var(--text-muted);">No active attacks</td></tr>';
            } else {
                attacksList.innerHTML = '';
                const now = new Date();
                attacks.forEach(attack => {
                    const endTime = new Date(attack.end_time);
                    const remaining = Math.max(0, Math.ceil((endTime - now) / 1000));
                    const row = document.createElement('tr');
                    row.innerHTML = `
                        <td>${attack.target}:${attack.port}</td>
                        <td>${attack.method}</td>
                        <td>${remaining}s</td>
                    `;
                    attacksList.appendChild(row);
                });
            }
        }

        const cooldownEnd = user.last_attack_time ? new Date(new Date(user.last_attack_time).getTime() + user.cooldown * 1000) : null;
        const now = new Date();
        if (cooldownEnd && cooldownEnd > now) {
            const remaining = Math.ceil((cooldownEnd - now) / 1000);
            startCooldownTimer(remaining);
        } else {
            startCooldownTimer(0);
        }

    } catch (error) {
        console.error('Failed to fetch dashboard info:', error);
    }
}

async function fetchMethods() {
    const headers = { 'Authorization': `Bearer ${getAuthToken()}`, 'Content-Type': 'application/json' };
    try {
        const response = await fetch('/api/methods', { headers });
        const data = await response.json();
        const methodSelect = document.getElementById('method');
        if (!methodSelect) return;
        methodSelect.innerHTML = '<option value="">Select a method</option>';
        for (const method in data) {
            const option = document.createElement('option');
            option.value = method;
            option.textContent = method;
            methodSelect.appendChild(option);
        }
    } catch (error) {
        console.error('Failed to fetch methods:', error);
    }
}

function handleDashboardPage() {
    if (!handleAuthPageSetup()) return;
    fetchDashboardInfo();
    setInterval(fetchDashboardInfo, 1000);
}

function handleAttackHubPage() {
    if (!handleAuthPageSetup()) return;

    const headers = { 'Authorization': `Bearer ${getAuthToken()}`, 'Content-Type': 'application/json' };
    const attackForm = document.getElementById('attack-form');
    const launchBtn = document.getElementById('launch-btn');

    // Initial data load
    fetchDashboardInfo();
    fetchMethods();
    setInterval(fetchDashboardInfo, 1000); // Keep running attacks list updated

    if (attackForm) {
        attackForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            launchBtn.disabled = true;
            launchBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Sending...';
            document.getElementById('error-message').style.display = 'none';

            const attackData = {
                target: document.getElementById('target').value,
                port: parseInt(document.getElementById('port').value, 10),
                duration: parseInt(document.getElementById('duration').value, 10),
                method: document.getElementById('method').value,
            };

            try {
                const response = await fetch('/api/attack', {
                    method: 'POST',
                    headers,
                    body: JSON.stringify(attackData),
                });
                const result = await response.json();
                if (response.ok) {
                    displayMessage('Attack launched successfully! Refreshing list...', 'success');
                    fetchDashboardInfo();
                } else {
                    displayMessage(result.error || 'Failed to launch attack.');
                }
            } catch (error) {
                displayMessage('An error occurred.');
            } finally {
                launchBtn.disabled = false;
                launchBtn.innerHTML = '<i class="fa-solid fa-paper-plane"></i> Send Attack';
            }
        });
    }
}

function handleIpLookupPage() {
    if (!handleAuthPageSetup()) return;

    const lookupForm = document.getElementById('lookup-form');
    if (lookupForm) {
        lookupForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const target = document.getElementById('lookup-target').value;
            const resultsEl = document.getElementById('lookup-results');
            const lookupBtn = document.getElementById('lookup-btn');
            
            lookupBtn.disabled = true;
            lookupBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Looking up...';
            resultsEl.style.display = 'block';
            resultsEl.textContent = 'Please wait...';
            displayMessage('', 'success'); // Clear previous messages

            try {
                // Using a free, public API for demonstration
                const response = await fetch(`https://ipapi.co/${target}/json/`);
                const data = await response.json();

                if (data.error) {
                    resultsEl.textContent = `Error: ${data.reason}`;
                } else {
                    // Format the JSON for pretty printing
                    resultsEl.textContent = JSON.stringify(data, null, 2);
                }
            } catch (err) {
                resultsEl.textContent = 'An error occurred during the lookup. The IP might be invalid or the service is down.';
            } finally {
                lookupBtn.disabled = false;
                lookupBtn.innerHTML = '<i class="fa-solid fa-search"></i> Lookup';
            }
        });
    }
}
