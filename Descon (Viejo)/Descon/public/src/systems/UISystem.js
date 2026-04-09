import TalentSystem from './TalentSystem.js';
import ChatSystem from './ChatSystem.js';
import PartySystem from './PartySystem.js';

export default class UISystem {
    constructor(scene) {
        this.scene = scene;
        this.lastHUDUpdate = 0;
        
        // Cargar configuración y posiciones v66.0
        this.hudConfig = this.scene.hudConfig || { chat: false, stats: false, minimap: false, skills: false, party: false };
        this.hudPositions = this.scene.hudPositions || {};
        
        this.setupGlobalFunctions();
        
        // Instanciar Sistemas Modulares v141.40
        this.chat = new ChatSystem(scene);
        this.party = new PartySystem(scene);
        this.talents = new TalentSystem(scene);

        this.applyHUDConfig();
    }

    get player() { return this.scene.player; }

    setupGlobalFunctions() {
        const elements = {
            chat: 'chat-container',
            stats: 'stats-hud',
            minimap: 'minimap-container',
            skills: 'skill-hud',
            party: 'party-hud',
            skillTree: 'tab-skills', 
            menu: 'equipment-menu'
        };

        window.toggleHUDElement = (type) => {
            if (type === 'menu') {
                const menu = document.getElementById(elements.menu);
                if (!menu) return;
                const isVisible = menu.style.display === 'block';
                menu.style.display = isVisible ? 'none' : 'block';
                window.isMenuOpen = !isVisible;
                if (!isVisible) {
                    this.scene.updateUI();
                    window.switchTab('hangar');
                }
                return;
            }

            const el = document.getElementById(elements[type]);
            const icon = document.getElementById(`icon-${type}`);
            if (el) {
                const isMin = el.classList.contains('minimized');
                if (isMin) { el.classList.remove('minimized'); icon?.classList.remove('minimized'); this.hudConfig[type] = false; }
                else { el.classList.add('minimized'); icon?.classList.add('minimized'); this.hudConfig[type] = true; }
                this.scene.saveProgress();
            }
        };

        window.toggleEquipmentMenu = () => window.toggleHUDElement('menu');

        window.switchTab = (tab) => {
            ['hangar', 'shop', 'party', 'skills'].forEach(t => {
                const el = document.getElementById(`tab-${t}`);
                if (el) el.style.display = t === tab ? 'block' : 'none';
            });
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            const tabBtn = document.getElementById(`tab-btn-${tab}`);
            if (tabBtn) tabBtn.classList.add('active');
            
            if (tab === 'skills') this.talents.render();
            if (tab === 'shop') this.renderShop();
            if (tab === 'hangar') this.renderHangar();
            if (tab === 'party') this.party.renderNearbyList();
            this.scene.updateUI(); 
        };

        window.openConfirmModal = (detail, onConfirm, title = '¿CONFIRMAR ADQUISICIÓN?') => {
            const modal = document.getElementById('confirmation-modal');
            const titleEl = document.getElementById('confirm-title');
            const detailEl = document.getElementById('confirm-item-details');
            const yesBtn = document.getElementById('confirm-yes');
            if (modal && titleEl && detailEl && yesBtn) {
                titleEl.innerText = title.toUpperCase();
                detailEl.innerHTML = detail;
                modal.style.setProperty('display', 'flex', 'important');
                yesBtn.onclick = (e) => {
                    e.stopPropagation();
                    onConfirm();
                    modal.style.setProperty('display', 'none', 'important');
                };
            }
        };

        window.showResultModal = (detail, title = '¡OPERACIÓN EXITOSA!') => {
            const modal = document.getElementById('result-modal');
            const titleEl = document.getElementById('result-title');
            const detailEl = document.getElementById('result-details');
            if (modal && titleEl && detailEl) {
                titleEl.innerText = title.toUpperCase();
                detailEl.innerHTML = detail;
                modal.style.setProperty('display', 'flex', 'important');
            }
        };

        window.selectAmmo = (type, tier) => {
            if (this.player) {
                this.player.selectedAmmo[type] = tier;
                window.hudNotify(`${type.toUpperCase()} L${tier+1} SELECCIONADO`, 'info');
                this.scene.updateUI();
                this.showAmmoOverlays(true);
                // v148.11: Persistencia Táctica (Anti-F5)
                if (this.scene.saveProgress) this.scene.saveProgress();
            }
        };

        window.closeConfirmModal = () => {
            const modal = document.getElementById('confirmation-modal');
            if (modal) modal.style.setProperty('display', 'none', 'important');
        };

        window.closeResultModal = () => {
            const modal = document.getElementById('result-modal');
            if (modal) modal.style.setProperty('display', 'none', 'important');
        };

        window.addEventListener('keydown', (e) => {
            if (e.key === 'F1') {
                e.preventDefault();
                window.toggleEquipmentMenu();
            }
        });
    }

    applyHUDConfig() {
        const elements = { chat: 'chat-container', stats: 'stats-hud', minimap: 'minimap-container', skills: 'skill-hud', party: 'party-hud' };
        Object.keys(this.hudConfig).forEach(id => {
            const target = document.getElementById(elements[id]);
            const icon = document.getElementById(`icon-${id}`);
            if (target && this.hudConfig[id]) {
                target.classList.add('minimized');
                if (icon) icon.classList.add('minimized');
            }
        });
        Object.keys(this.hudPositions).forEach(id => {
            const el = document.getElementById(elements[id]);
            const pos = this.hudPositions[id];
            if (el && pos) {
                el.style.top = pos.top; el.style.left = pos.left; el.style.bottom = pos.bottom; el.style.right = pos.right;
            }
        });
    }

    showAmmoOverlays(show) {
        ['q','w','e'].forEach(k => {
            const el = document.getElementById(`overlay-${k}`);
            if (!el) return;
            el.style.display = show ? 'flex' : 'none';
            if (show) {
                const type = k === 'q' ? 'laser' : (k === 'w' ? 'missile' : 'mine');
                el.innerHTML = '';
                for (let i = 0; i < 6; i++) {
                    const opt = document.createElement('div');
                    opt.className = 'ammo-option' + (this.player.selectedAmmo[type] === i ? ' active' : '');
                    opt.innerText = `T${i+1}: ${(this.player.ammo[type][i] || 0).toLocaleString()}`;
                    opt.onclick = (e) => { e.stopPropagation(); window.selectAmmo(type, i); };
                    el.appendChild(opt);
                }
            }
        });
    }

    forceHUDUpdate() {
        if (!this.player) return;
        const now = this.scene.app.ticker.lastTime;
        this.update(now, 1);
    }

    update(time, delta) {
        if (!this.player) return;
        
        // v146.61: Refresco dinámico forzado para HP/SH/Allies
        this.lastHUDUpdate = time;
        this.party.updateHUD();
        
        const hpPct = this.player.maxHp > 0 ? (this.player.hp / this.player.maxHp) * 100 : 0;
        const shPct = this.player.maxShield > 0 ? (this.player.shield / this.player.maxShield) * 100 : 0;
        
        const elements = {
            hpFill: 'hp-bar-fill', shFill: 'sh-bar-fill', hpVal: 'hp-val', shVal: 'sh-val',
            hubsVal: 'hubs-val', ohcuVal: 'ohcu-val', fpsVal: 'fps-val', onlineVal: 'online-count',
            lvlVal: 'level-val', expBar: 'exp-bar-fill', expPct: 'exp-pct'
        };

        const updateEl = (id, val, attr = 'innerText') => {
            const el = document.getElementById(id);
            if (el) el[attr] = val;
        };

        updateEl(elements.hpFill, `${Math.max(0, hpPct)}%`, 'style.width');
        updateEl(elements.shFill, `${Math.max(0, shPct)}%`, 'style.width');
        updateEl(elements.hpVal, Math.ceil(this.player.hp).toLocaleString());
        updateEl(elements.shVal, Math.ceil(this.player.shield).toLocaleString());
        updateEl(elements.hubsVal, Math.floor(this.scene.hubs || 0).toLocaleString());
        updateEl(elements.ohcuVal, Math.floor(this.scene.ohculianos || 0).toLocaleString());
        updateEl(elements.fpsVal, Math.floor(this.scene.app.ticker.FPS));
        updateEl(elements.onlineVal, (this.scene.entities.remotePlayers ? this.scene.entities.remotePlayers.size : 0) + 1);
        updateEl(elements.lvlVal, this.player.level || 1);
        updateEl(elements.expBar, `${(this.player.exp / this.player.nextLevelExp) * 100}%`, 'style.width');
        updateEl(elements.expPct, `${Math.floor((this.player.exp / this.player.nextLevelExp) * 100)}%`);

        // Skills Cooldowns
        const nowTime = Date.now();
        ['laser', 'missile', 'mine'].forEach((type, i) => {
            const key = ['q','w','e'][i];
            const diff = nowTime - this.player.lastShootTimes[type];
            const delay = this.player.shootDelays[type];
            const pct = Math.max(0, Math.min(1, 1 - (diff / delay)));
            const remaining = Math.max(0, (delay - diff) / 1000);
            
            const fill = document.getElementById(`slot-${key}-fill`);
            if (fill) fill.style.height = `${pct * 100}%`;
            
            const timer = document.getElementById(`slot-${key}-timer`);
            if (timer) {
                timer.innerText = remaining > 0 ? remaining.toFixed(1) + 's' : '';
                timer.style.color = remaining > 0 ? '#ff3333' : 'var(--neon-green)';
            }
            
            const ammoTag = document.getElementById(`ammo-${key}`);
            if (ammoTag && this.player.ammo && this.player.ammo[type]) {
                const current = this.player.ammo[type][this.player.selectedAmmo[type]] || 0;
                ammoTag.innerText = current.toLocaleString();
            }
        });
    }

    renderHangar() { if (this.scene.hangarSystem) this.scene.hangarSystem.render(); }
    renderShop() { if (this.scene.shopSystem) this.scene.shopSystem.render(); }
}
