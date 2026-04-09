// GESTIÓN DE SESIÓN Y AUTH CON MONGO DB
const socket = io();
window.socket = socket;

// Cargar sesión guardada al iniciar
window.onload = () => {
    const saved = localStorage.getItem('descon_session');
    if (saved) {
        const { user, pass } = JSON.parse(saved);
        document.getElementById('login-user').value = user;
        document.getElementById('login-pass').value = pass;
        document.getElementById('keep-logged').checked = true;
    }

    // Mostrar error de expulsión si existe
    const kickMsg = sessionStorage.getItem('descon_error_msg');
    if (kickMsg) {
        const errorEl = document.getElementById('login-error');
        if (errorEl) {
            errorEl.innerText = kickMsg;
            errorEl.style.color = "#ff3333";
        }
        sessionStorage.removeItem('descon_error_msg');
    }
};

window.handleAuth = async (type) => {
    const user = document.getElementById('login-user').value.trim();
    const pass = document.getElementById('login-pass').value.trim();
    const keep = document.getElementById('keep-logged').checked;
    const errorEl = document.getElementById('login-error');
    
    if (!user || !pass) {
        errorEl.innerText = "COMPLETA TODOS LOS CAMPOS";
        return;
    }

    if (keep) {
        localStorage.setItem('descon_session', JSON.stringify({ user, pass }));
    } else {
        localStorage.removeItem('descon_session');
    }

    errorEl.innerText = "CONECTANDO...";
    socket.emit(type, { user, password: pass });
};

socket.on('authError', (msg) => {
    const errorEl = document.getElementById('login-error');
    if (errorEl) {
        errorEl.innerText = msg;
        errorEl.style.color = "#ff3333";
    }
    
    // Si ya estábamos jugando, forzar el regreso al login por seguridad (Anti-MultiLogin)
    const overlay = document.getElementById('login-overlay');
    if (overlay && overlay.style.display === 'none') {
        overlay.style.display = 'flex';
        // Guardar mensaje en sessionStorage para mostrarlo tras recargar
        sessionStorage.setItem('descon_error_msg', msg);
        setTimeout(() => location.reload(), 500); // Reinicio forzado por seguridad v33.2
    }
});

socket.on('authSuccess', (data) => {
    document.getElementById('login-error').style.color = "var(--neon-green)";
    document.getElementById('login-error').innerText = data.msg;
    setTimeout(() => {
        const user = document.getElementById('login-user').value;
        const pass = document.getElementById('login-pass').value;
        socket.emit('login', { user, password: pass });
    }, 1000);
});

socket.on('loginSuccess', (data) => {
    window.loggedUser = data.user;
    window.loggedId = data.id; // DNI Galáctico v123.40
    window.loggedSocketId = data.socketId; // ID Volátil v123.40
    window.pendingGameData = data.gameData;
    window.globalAdminConfig = data.adminConfig; 
    
    document.getElementById('login-overlay').style.display = 'none';
    
    // Lanzar el juego solo cuando hay datos
    if (window.initGame) {
        window.initGame();
    } else {
        console.error("Error: El motor de juego no se ha cargado correctamente.");
    }
});

window.hudNotify = (msg, type = 'info') => {
    const cont = document.getElementById('hud-notifier');
    if (!cont) return;

    // Lógica de Apilamiento Táctico v69.3
    const last = cont.lastElementChild;
    if (last && last.getAttribute('data-msg') === msg) {
        const count = parseInt(last.getAttribute('data-count') || "1") + 1;
        last.setAttribute('data-count', count);
        last.innerText = `${msg} x${count}`;
        
        // Resetear expiración
        if (last.timer) clearTimeout(last.timer);
        last.timer = setTimeout(() => {
            last.style.animation = 'hudFadeOut 0.5s forwards';
            setTimeout(() => last.remove(), 500);
        }, 4000);
        return;
    }

    const div = document.createElement('div');
    div.className = `hud-msg ${type}`;
    div.innerText = msg;
    div.setAttribute('data-msg', msg);
    div.setAttribute('data-count', "1");
    cont.appendChild(div);

    div.timer = setTimeout(() => {
        div.style.animation = 'hudFadeOut 0.5s forwards';
        setTimeout(() => div.remove(), 500);
    }, 4000);
};
