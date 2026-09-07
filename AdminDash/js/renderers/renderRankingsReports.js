// AdminDash/js/renderers/renderRankingsReports.js
function renderRanking() {
    if (!config.rankingConfig) {
        config.rankingConfig = JSON.parse(JSON.stringify(DEFAULT_RANKING_CONFIG));
    }
    const rc = config.rankingConfig;

    const configContainer = document.getElementById('ranking-config-container');
    const listContainer = document.getElementById('ranking-categories-container');
    if (!configContainer || !listContainer) return;

    const f = getFilter();

    // ── Config Global ──
    configContainer.innerHTML = `
        <div class="card" style="width: 100%;">
            <h3 style="color: var(--primary); margin-bottom: 1.5rem; display: flex; align-items: center; gap: 10px;">
                🏆 CONFIGURACIÓN GLOBAL DE CLASIFICACIÓN
            </h3>
            <p style="font-size:0.85rem; color:#aaa; margin-bottom:1.5rem; line-height:1.4;">
                Configurá las categorías de ranking, las recompensas por posición y el intervalo de reinicio.
                Cada categoría acumula puntos de forma independiente (<strong style="color:var(--accent);">Monstruos</strong>, 
                <strong style="color:var(--accent);">Eventos</strong>, <strong style="color:var(--accent);">Nivel</strong>).
                Los puntos de ranking por monstruo se configuran en el editor de cada enemigo.
            </p>
        </div>
        <div class="card" style="width: 100%; border-color: rgba(6,182,212,0.2); background: rgba(6,182,212,0.03);">
            <div style="display:flex; justify-content:space-between; align-items:center;">
                <h3 style="color: var(--accent); margin:0; display: flex; align-items: center; gap: 10px;">
                    📊 VISTA PREVIA DEL RANKING
                </h3>
                <button class="btn btn-primary" onclick="emitGetRankings()" style="padding: 8px 16px; font-size: 0.75rem;">
                    🔄 REFRESCAR DATOS
                </button>
            </div>
            <div id="ranking-preview" style="margin-top: 1rem; font-size: 0.85rem; color: #aaa;">
                Seleccioná una categoría abajo y presioná "VER RANKING" para ver los líderes actuales.
            </div>
        </div>
    `;

    // ── Categorías ──
    listContainer.innerHTML = '';

    const headerCard = document.createElement('div');
    headerCard.className = 'card';
    headerCard.style.width = '100%';
    headerCard.style.marginBottom = '1.5rem';
    headerCard.innerHTML = `
        <h3 style="color: var(--primary); margin-bottom: 1rem; display: flex; align-items: center; gap: 10px;">
            🏅 CATEGORÍAS DE CLASIFICACIÓN
            <button class="btn btn-primary" style="padding: 4px 12px; font-size: 0.7rem;" onclick="addRankingCategory()">+ AGREGAR CATEGORÍA</button>
        </h3>
        <p style="font-size:0.85rem; color:#aaa; line-height:1.4;">
            Cada categoría tiene su propia tabla de posiciones y recompensas. 
            Los intervalos de reinicio definen cada cuánto se reparten las recompensas y se resetean los puntajes.
        </p>
    `;
    listContainer.appendChild(headerCard);

    const categoriesDiv = document.createElement('div');
    categoriesDiv.style.display = 'flex';
    categoriesDiv.style.flexDirection = 'column';
    categoriesDiv.style.gap = '2rem';
    listContainer.appendChild(categoriesDiv);

    const categories = rc.categories || [];
    categories.forEach((cat, catIdx) => {
        if (f && !cat.name.toLowerCase().includes(f) && !cat.id.toLowerCase().includes(f)) return;

        const catCard = document.createElement('div');
        catCard.className = 'card';
        catCard.style.position = 'relative';
        catCard.style.borderLeft = '4px solid var(--accent)';

        if (!cat.rewards) cat.rewards = [];

        let rewardsHTML = cat.rewards.map((rw, rIdx) => {
            let itemsHTML = (rw.items || []).map((item, iIdx) => `
                <div style="display:flex; gap:8px; align-items:center; margin-bottom:4px; background:rgba(255,255,255,0.02); padding:4px 8px; border-radius:6px;">
                    <div class="field" style="margin:0; flex:2;"><label style="font-size:8px;">ID Ítem</label><input type="text" value="${item.id}" style="font-size:0.7rem; padding:3px;" onchange="config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].items[${iIdx}].id = this.value"></div>
                    <div class="field" style="margin:0; flex:1;"><label style="font-size:8px;">Cant.</label><input type="number" value="${item.qty}" style="font-size:0.7rem; padding:3px;" onchange="config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].items[${iIdx}].qty = Math.floor(Math.max(1, parseInt(this.value) || 1))"></div>
                    <button class="btn" style="background:var(--danger); border:none; padding:2px 6px; font-size:9px; margin-top:12px; cursor:pointer;" onclick="config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].items.splice(${iIdx}, 1); renderRanking();">✕</button>
                </div>
            `).join('');

            return `
                <div style="background:rgba(0,0,0,0.2); border-radius:12px; padding:1rem; margin-bottom:0.8rem; border:1px solid rgba(255,255,255,0.05); position:relative;">
                    <div style="position:absolute; top:8px; right:8px; display:flex; gap:6px;">
                        <button style="background:none; border:none; color:#ff4444; cursor:pointer; font-size:0.8rem;" onclick="removeRankingReward(${catIdx}, ${rIdx})" title="Eliminar posición">✕</button>
                    </div>
                    <div style="display:flex; align-items:center; gap:12px; margin-bottom:0.8rem;">
                        <span style="background:var(--accent); color:#000; font-weight:bold; font-size:0.8rem; padding:4px 12px; border-radius:20px;">#${rw.rank}</span>
                        <span style="color:var(--text-dim); font-size:0.75rem;">POSICIÓN</span>
                    </div>
                    <div class="form-grid" style="grid-template-columns: 1fr 1fr 1fr 1fr 1fr; gap:8px;">
                        <div class="field"><label>Hubs</label><input type="number" value="${rw.hubs || 0}" onchange="config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].hubs = parseInt(this.value)"></div>
                        <div class="field"><label>OHCU</label><input type="number" value="${rw.ohcu || 0}" onchange="config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].ohcu = parseInt(this.value)"></div>
                        <div class="field"><label>EXP</label><input type="number" value="${rw.exp || 0}" onchange="config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].exp = parseInt(this.value)"></div>
                        <div class="field"><label>EXP BP</label><input type="number" value="${rw.bpExp || 0}" onchange="config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].bpExp = parseInt(this.value)"></div>
                    </div>
                    <div style="margin-top:0.5rem;">
                        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:4px;">
                            <label style="font-size:9px; color:var(--text-dim);">📦 Ítems</label>
                            <button class="btn btn-primary" style="padding:2px 8px; font-size:8px;" onclick="if(!config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].items) config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].items = []; config.rankingConfig.categories[${catIdx}].rewards[${rIdx}].items.push({id:'', qty:1}); renderRanking();">+ Item</button>
                        </div>
                        <div style="max-height:100px; overflow-y:auto;">
                            ${itemsHTML}
                        </div>
                    </div>
                </div>
            `;
        }).join('');

        const resetOptions = [
            { value: 'daily', label: 'Diario' },
            { value: 'weekly', label: 'Semanal' },
            { value: 'monthly', label: 'Mensual' },
            { value: 'never', label: 'Nunca (manual)' }
        ];

        catCard.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1.2rem; padding-bottom:0.8rem; border-bottom:1px solid rgba(255,255,255,0.05);">
                <div style="font-family:'JetBrains Mono'; font-size:0.7rem; color:var(--text-dim); opacity:0.6;">ID: ${cat.id}</div>
                <div style="display:flex; gap:8px; align-items:center;">
                    <button class="btn btn-primary" style="padding:4px 10px; font-size:0.6rem; background:rgba(6,182,212,0.2); border:1px solid rgba(6,182,212,0.3); color:var(--accent);" onclick="viewRankingPreview('${cat.id}')">📊 VER RANKING</button>
                    <button class="btn btn-danger" style="padding:4px 10px; font-size:0.6rem;" onclick="removeRankingCategory(${catIdx})">✕ ELIMINAR</button>
                </div>
            </div>
            <div style="margin-bottom:1.5rem; display:flex; align-items:center; gap:15px;">
                <div style="font-size:2.5rem; line-height:1;">${cat.icon || '🏆'}</div>
                <div style="flex:1;">
                    <div class="form-grid" style="grid-template-columns: 1fr 1fr 1fr; gap:12px;">
                        <div class="field">
                            <label>Nombre</label>
                            <input type="text" value="${cat.name}" onchange="config.rankingConfig.categories[${catIdx}].name = this.value">
                        </div>
                        <div class="field">
                            <label>Icono</label>
                            <input type="text" value="${cat.icon || ''}" placeholder="Ej: 👾" onchange="config.rankingConfig.categories[${catIdx}].icon = this.value" style="font-size:1.2rem;">
                        </div>
                        <div class="field">
                            <label>Intervalo de Reinicio</label>
                            <select onchange="config.rankingConfig.categories[${catIdx}].resetInterval = this.value; renderRanking();" style="background:#0f172a; border:1px solid rgba(255,255,255,0.1); border-radius:8px; padding:8px; color:white; outline:none; width:100%;">
                                ${resetOptions.map(opt => `<option value="${opt.value}" ${cat.resetInterval === opt.value ? 'selected' : ''}>${opt.label}</option>`).join('')}
                            </select>
                        </div>
                    </div>
                </div>
            </div>

            <div style="border-top:1px solid rgba(255,255,255,0.05); padding-top:1rem;">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;">
                    <h4 style="color:var(--accent); font-size:0.8rem; font-weight:bold; margin:0;">🎁 RECOMPENSAS POR POSICIÓN</h4>
                    <button class="btn btn-primary" style="padding:4px 12px; font-size:0.65rem;" onclick="addRankingReward(${catIdx})">+ AGREGAR POSICIÓN</button>
                </div>
                <div style="display:flex; flex-direction:column; gap:4px;">
                    ${rewardsHTML || '<div style="color:#555; font-style:italic; font-size:0.8rem; padding:0.5rem;">No hay recompensas configuradas. Hacé clic en "+ AGREGAR POSICIÓN".</div>'}
                </div>
            </div>
        `;
        categoriesDiv.appendChild(catCard);
    });

    if (categories.length === 0) {
        const emptyMsg = document.createElement('div');
        emptyMsg.style.cssText = 'color:#555; font-style:italic; padding:2rem; text-align:center; font-size:0.9rem;';
        emptyMsg.innerText = 'No hay categorías de ranking. Hacé clic en "+ AGREGAR CATEGORÍA" para comenzar.';
        categoriesDiv.appendChild(emptyMsg);
    }
}

// ─── FUNCIONES GLOBALES DE RANKING ───

window.addRankingCategory = function() {
    if (!config.rankingConfig) {
        config.rankingConfig = JSON.parse(JSON.stringify(DEFAULT_RANKING_CONFIG));
    }
    if (!config.rankingConfig.categories) config.rankingConfig.categories = [];

    const newId = 'cat_' + Date.now();
    config.rankingConfig.categories.push({
        id: newId,
        name: 'Nueva Categoría',
        icon: '🏆',
        resetInterval: 'weekly',
        rewards: [
            { rank: 1, hubs: 10000, ohcu: 50, exp: 5000, bpExp: 2000, items: [] },
            { rank: 2, hubs: 5000, ohcu: 25, exp: 2500, bpExp: 1000, items: [] },
            { rank: 3, hubs: 2500, ohcu: 10, exp: 1000, bpExp: 500, items: [] }
        ]
    });
    renderRanking();
};

window.removeRankingCategory = function(catIdx) {
    if (!config.rankingConfig || !config.rankingConfig.categories) return;
    config.rankingConfig.categories.splice(catIdx, 1);
    renderRanking();
};

window.addRankingReward = function(catIdx) {
    if (!config.rankingConfig || !config.rankingConfig.categories) return;
    const cat = config.rankingConfig.categories[catIdx];
    if (!cat) return;
    if (!cat.rewards) cat.rewards = [];

    const nextRank = cat.rewards.length > 0 ? Math.max(...cat.rewards.map(r => r.rank)) + 1 : 1;
    cat.rewards.push({
        rank: nextRank,
        hubs: 0,
        ohcu: 0,
        exp: 0,
        bpExp: 0,
        items: []
    });
    renderRanking();
};

window.removeRankingReward = function(catIdx, rIdx) {
    if (!config.rankingConfig || !config.rankingConfig.categories) return;
    const cat = config.rankingConfig.categories[catIdx];
    if (!cat || !cat.rewards) return;
    cat.rewards.splice(rIdx, 1);
    // Re-indexar ranks
    cat.rewards.forEach((r, i) => r.rank = i + 1);
    renderRanking();
};

window.viewRankingPreview = function(categoryId) {
    const preview = document.getElementById('ranking-preview');
    if (!preview) return;
    preview.innerHTML = `<div style="color:#888; font-style:italic;">Solicitando datos del ranking <strong>${categoryId}</strong>...</div>`;

    if (typeof socket !== 'undefined' && socket && socket.connected) {
        socket.off('rankingsData');
        socket.on('rankingsData', (data) => {
            if (data.category !== categoryId) return;
            if (!data.rankings || data.rankings.length === 0) {
                preview.innerHTML = `<div style="color:#555; font-style:italic;">No hay datos de ranking para esta categoría aún.</div>`;
                return;
            }
            let html = `<div style="display:flex; flex-direction:column; gap:6px;">`;
            const medals = ['🥇', '🥈', '🥉'];
            data.rankings.forEach((entry, idx) => {
                const medal = idx < 3 ? medals[idx] : `#${idx + 1}`;
                html += `
                    <div style="display:flex; align-items:center; gap:12px; background:rgba(255,255,255,0.02); padding:8px 12px; border-radius:8px; border:1px solid rgba(255,255,255,0.05);">
                        <span style="font-size:1.2rem;">${medal}</span>
                        <strong style="flex:1; color:var(--text);">${entry.username}</strong>
                        <span style="color:var(--accent); font-weight:bold; font-family:'JetBrains Mono';">${entry.points} pts</span>
                    </div>
                `;
            });
            html += `</div>`;
            preview.innerHTML = html;
        });
        socket.emit('getRankings', { category: categoryId });
    } else {
        preview.innerHTML = `<div style="color:#ff4444;">ERROR: No hay conexión con el servidor.</div>`;
    }
};

window.emitGetRankings = function() {
    const preview = document.getElementById('ranking-preview');
    if (preview) {
        preview.innerHTML = `<div style="color:#888; font-style:italic;">Seleccioná una categoría y hacé clic en "VER RANKING".</div>`;
    }
};



// v1.1: REPORTES DE BUGS (local + cloud)
let lastBugReports = [];
function mergeBugReports(incoming, replaceSource, source) {
    // Autoritativo: si es un listado completo (replaceSource), reemplaza TODOS los
    // reportes de esa fuente (así un reporte eliminado en el servidor desaparece en
    // vivo, incluso si la lista queda vacía).
    if (replaceSource && source) {
        lastBugReports = lastBugReports.filter(x => x.source !== source);
    }
    for (const r of incoming) {
        const existing = lastBugReports.findIndex(x => x.source === r.source && String(x.id) === String(r.id));
        if (existing >= 0) lastBugReports[existing] = r;
        else lastBugReports.push(r);
    }
    lastBugReports.sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));
    renderBugReports(lastBugReports);
}

function renderBugReports(data) {
    if (data) lastBugReports = data;
    const list = document.getElementById('bugreports-list');
    if (!list) return;
    list.innerHTML = '';
    const f = getFilter();

    if (lastBugReports.length === 0) {
        list.innerHTML = '<div style="color:#666; font-style:italic; padding:2rem; text-align:center;">No hay reportes de bugs todavía.</div>';
        return;
    }

    lastBugReports.forEach(r => {
        if (f) {
            const hay = (r.nick + ' ' + r.email + ' ' + r.phone + ' ' + r.description).toLowerCase();
            if (!hay.includes(f)) return;
        }

        const card = document.createElement('div');
        card.className = 'card';
        card.style.cssText = 'width:100%; border-left:3px solid ' + (r.status === 'closed' ? '#ff3b30' : (r.status === 'resolved' ? 'var(--success)' : '#f0a500')) + ';';

        const fecha = r.createdAt ? new Date(r.createdAt).toLocaleString('es-AR', { day:'2-digit', month:'2-digit', year:'2-digit', hour:'2-digit', minute:'2-digit', hour12:false }) : '--';

        const header = document.createElement('div');
        header.style.cssText = 'display:flex; justify-content:space-between; align-items:center; gap:1rem; margin-bottom:0.75rem; flex-wrap:wrap;';
        const srcTag = r.source === 'cloud'
            ? '<span class="card-tag" style="position:static; background:rgba(240,165,0,0.12); color:#f0a500; border:1px solid rgba(240,165,0,0.2);">☁️ SERVER</span>'
            : '<span class="card-tag" style="position:static; background:rgba(0,210,255,0.12); color:var(--primary); border:1px solid rgba(0,210,255,0.2);">💻 LOCAL</span>';
        
        let statusBadgeColor = 'rgba(240,165,0,0.1); color:#f0a500;';
        let statusText = '⏳ ABIERTO';
        if (r.status === 'resolved') {
            statusBadgeColor = 'rgba(59,255,49,0.1); color:#3bff31;';
            statusText = '✅ RESUELTO';
        } else if (r.status === 'closed') {
            statusBadgeColor = 'rgba(255,59,48,0.1); color:#ff3b30;';
            statusText = '🏁 FINALIZADO';
        }

        let actionsHTML = '';
        if (r.status !== 'closed') {
            actionsHTML += '<button class="btn btn-secondary" onclick="setBugReportStatus(' + r.id + ', \'' + (r.status === 'resolved' ? 'open' : 'resolved') + '\', \'' + (r.source || 'local') + '\')">' + (r.status === 'resolved' ? '↩️ REABRIR' : '✅ MARCAR RESUELTO') + '</button>';
            actionsHTML += '<button class="btn" style="background:#ff9500; color:#000; border:none; padding:6px 12px; border-radius:6px; cursor:pointer; font-weight:bold; font-size:0.75rem; margin:0;" onclick="closeBugReport(' + r.id + ', \'' + (r.source || 'local') + '\')">🏁 FINALIZAR</button>';
        }
        actionsHTML += '<button class="btn btn-danger" onclick="deleteBugReport(' + r.id + ', \'' + (r.source || 'local') + '\')">🗑️ ELIMINAR</button>';

        header.innerHTML = '<div style="display:flex; align-items:center; gap:10px; flex-wrap:wrap;">' +
            srcTag +
            '<strong style="color:var(--primary); font-size:1.05rem;">#' + r.id + ' • ' + escapeHtml(String(r.nick || 'Desconocido').toUpperCase()) + '</strong>' +
            '<span class="card-tag" style="position:static; background:rgba(0,210,255,0.1); color:var(--primary);">' + fecha + '</span>' +
            '<span class="card-tag" style="position:static; background:rgba(255,255,255,0.05); color:#999;">SECTOR ' + (Number(r.zone) || 1) + ' · LVL ' + (Number(r.level) || 1) + '</span>' +
            '<span class="card-tag" style="position:static; background:' + statusBadgeColor + '">' + statusText + '</span>' +
            '</div>' +
            '<div style="display:flex; gap:8px; align-items:center;">' +
            actionsHTML +
            '</div>';
        card.appendChild(header);

        const meta = document.createElement('div');
        meta.style.cssText = 'display:flex; flex-direction:column; gap:4px; margin-bottom:0.75rem; font-size:0.85rem;';
        meta.innerHTML = '<div><span style="color:#888;">EMAIL:</span> <strong style="color:var(--text);">' + escapeHtml(r.email || '') + '</strong></div>' +
            '<div><span style="color:#888;">CELULAR:</span> <strong style="color:var(--text);">' + escapeHtml(r.phone || 'Sin especificar') + '</strong></div>';
        card.appendChild(meta);

        const desc = document.createElement('div');
        desc.style.cssText = 'background:rgba(0,0,0,0.25); border:1px solid rgba(255,255,255,0.05); border-radius:10px; padding:12px 16px; white-space:pre-wrap; word-break:break-word; font-size:0.9rem; line-height:1.5; color:#ddd; margin-bottom:0.75rem;';
        desc.textContent = r.description || '';
        card.appendChild(desc);

        if (r.images && r.images.length > 0) {
            const imgs = document.createElement('div');
            imgs.style.cssText = 'display:flex; gap:10px; flex-wrap:wrap;';
            r.images.forEach(img => {
                const dataUrl = 'data:' + (img.mime || 'image/png') + ';base64,' + img.data;
                const wrap = document.createElement('div');
                wrap.style.cssText = 'position:relative;';
                const pic = document.createElement('img');
                pic.src = dataUrl;
                pic.alt = img.name || 'imagen';
                pic.style.cssText = 'max-height:160px; max-width:220px; border-radius:8px; border:1px solid rgba(255,255,255,0.15); cursor:zoom-in;';
                pic.onclick = () => {
                    const overlay = document.createElement('div');
                    overlay.style.cssText = 'position:fixed; inset:0; background:rgba(0,0,0,0.92); z-index:9999; display:flex; align-items:center; justify-content:center; cursor:zoom-out;';
                    const big = document.createElement('img');
                    big.src = dataUrl;
                    big.style.cssText = 'max-width:92vw; max-height:92vh; border-radius:8px;';
                    overlay.appendChild(big);
                    overlay.onclick = () => overlay.remove();
                    document.body.appendChild(overlay);
                };
                wrap.appendChild(pic);
                const cap = document.createElement('div');
                cap.style.cssText = 'font-size:0.7rem; color:#888; text-align:center; margin-top:4px; max-width:220px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;';
                cap.textContent = img.name || '';
                wrap.appendChild(cap);
                imgs.appendChild(wrap);
            });
            card.appendChild(imgs);
        }

        // --- HILO DE CONVERSACIÓN (CHAT) ---
        const chatContainer = document.createElement('div');
        chatContainer.style.cssText = 'margin-top:10px; display:flex; flex-direction:column; gap:8px; padding:10px; background:rgba(0,0,0,0.15); border-radius:8px; border:1px solid rgba(255,255,255,0.03);';
        
        // Mensaje inicial del usuario (Descripción)
        const initialBubble = document.createElement('div');
        initialBubble.style.cssText = 'padding:8px 12px; border-radius:8px; max-width:85%; font-size:0.85rem; line-height:1.4; background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.1); align-self:flex-start; color:#ddd;';
        initialBubble.innerHTML = '<strong style="color:var(--primary); font-size:0.75rem; display:block; margin-bottom:2px;">' + escapeHtml(r.nick.toUpperCase()) + ' (REPORTE ORIGINAL)</strong>' + escapeHtml(r.description || '');
        chatContainer.appendChild(initialBubble);

        if (r.replies && r.replies.length > 0) {
            r.replies.forEach(rep => {
                const bubble = document.createElement('div');
                const isAdmin = rep.sender === 'admin';
                bubble.style.cssText = 'padding:8px 12px; border-radius:8px; max-width:85%; font-size:0.85rem; line-height:1.4; ' +
                    (isAdmin 
                        ? 'background:rgba(6,182,212,0.15); border:1px solid rgba(6,182,212,0.3); align-self:flex-end; color:#fff;' 
                        : 'background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.1); align-self:flex-start; color:#ddd;');
                
                bubble.innerHTML = '<strong style="color:' + (isAdmin ? 'var(--accent)' : 'var(--primary)') + '; font-size:0.75rem; display:block; margin-bottom:2px;">' +
                    (isAdmin ? 'SOPORTE' : escapeHtml(r.nick.toUpperCase())) + '</strong>' +
                    escapeHtml(rep.text);
                chatContainer.appendChild(bubble);
            });
        }
        card.appendChild(chatContainer);

        // Bloque de respuesta (ocultar si está cerrado)
        if (r.status !== 'closed') {
            const replyBlock = document.createElement('div');
            replyBlock.style.cssText = 'margin-top:1rem; padding-top:1rem; border-top:1px dashed rgba(255,255,255,0.08);';
            replyBlock.innerHTML = 
                '<div style="display:flex; gap:10px; align-items:flex-end;">' +
                    '<div style="flex:1;">' +
                        '<label style="font-size:0.75rem; color:#888; display:block; margin-bottom:4px;">RESPONDER AL JUGADOR (IN-GAME BUZÓN):</label>' +
                        '<textarea id="reply-input-' + r.id + '-' + r.source + '" rows="2" placeholder="Escribí tu respuesta de soporte..." style="width:100%; background:rgba(0,0,0,0.3); border:1px solid rgba(255,255,255,0.1); border-radius:6px; color:#fff; padding:8px; font-size:0.85rem; resize:vertical; box-sizing:border-box; outline:none;"></textarea>' +
                    '</div>' +
                    '<button class="btn btn-primary" onclick="submitBugReply(' + r.id + ', \'' + r.source + '\')" style="padding:10px 16px; font-size:0.8rem; height:fit-content; background:var(--accent); color:#000; font-weight:bold; border-radius:6px; cursor:pointer; border:none; margin:0;">✉️ ENVIAR</button>' +
                '</div>';
            card.appendChild(replyBlock);
        } else {
            const closedInfo = document.createElement('div');
            closedInfo.style.cssText = 'margin-top:1rem; padding:8px; background:rgba(255,59,48,0.1); border:1px solid rgba(255,59,48,0.2); border-radius:6px; color:#ff3b30; text-align:center; font-size:0.85rem; font-weight:bold;';
            closedInfo.innerText = '🏁 REPORTE FINALIZADO Y CERRADO';
            card.appendChild(closedInfo);
        }

        list.appendChild(card);
    });
}

function escapeHtml(str) {
    return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}
