export default class PartySystem {
    constructor(scene) {
        this.scene = scene;
        this.init();
    }

    get player() { return this.scene.player; }

    init() {
        this.scene.events.on('partyInvitation', (data) => {
            const modal = document.getElementById('party-invite-modal');
            const text = document.getElementById('party-invite-text');
            const acceptBtn = document.getElementById('party-accept-btn');
            if (modal && text && acceptBtn) {
                text.innerText = `${data.from} te ha invitado a su grupo de combate.`;
                acceptBtn.onclick = () => {
                    this.scene.socketManager.socket.emit('acceptParty', data.fromId);
                    modal.style.display = 'none';
                };
                modal.style.display = 'flex';
            }
        });

        this.scene.events.on('partyUpdate', (party) => {
            this.scene.currentParty = party;
            this.renderTab();
        });
        
        this.scene.events.on('spawnRemotePlayer', () => this.renderNearbyList());
        this.scene.events.on('removeRemotePlayer', () => this.renderNearbyList());

        // Exponer funciones globales v141.30
        window.inviteToParty = (name) => this.invite(name);
        window.leaveParty = () => this.leave();
        window.updateNearbyPlayersUI = () => this.renderNearbyList();
    }

    invite(name) {
        const input = document.getElementById('party-invite-input');
        const target = name || (input ? input.value.trim() : '');
        if (target && target.length > 0) {
            this.scene.socketManager.socket.emit('inviteToParty', target);
            window.hudNotify(`INVITACIÓN ENVIADA A ${target.toUpperCase()}`, 'info');
            if (input) input.value = '';
        }
    }

    leave() {
        this.scene.socketManager.socket.emit('leaveParty');
        window.hudNotify('HAS ABANDONADO EL GRUPO', 'error');
        const btn = document.getElementById('leave-party-btn');
        if (btn) btn.style.display = 'none';
    }

    renderNearbyList() {
        const list = document.getElementById('nearby-players-list');
        const partyTab = document.getElementById('tab-party');
        if (!list || !partyTab || (partyTab.style.display === 'none' && !window.equipmentMenuOpen)) return;
        
        list.innerHTML = '';
        const remotes = this.scene.entities.remotePlayers;
        if (!remotes || remotes.size === 0) {
            list.innerHTML = '<div style="color: #666; font-size: 10px; text-align: center; margin-top: 20px;">No hay otros pilotos en esta zona compartida.</div>';
            return;
        }

        remotes.forEach((player, id) => {
            const name = (player.userData && typeof player.userData === 'object') ? (player.userData.user || 'Piloto') : (player.userData || 'Piloto');
            const row = document.createElement('div');
            row.style.cssText = 'display: flex; justify-content: space-between; align-items: center; padding: 6px 10px; background: rgba(0,255,0,0.05); border: 1px solid rgba(0,255,0,0.1); border-radius: 4px; margin-bottom: 2px;';
            
            const nameSpan = document.createElement('span');
            nameSpan.style.cssText = 'color: #88ff88; font-family: "Outfit"; font-size: 11px; font-weight: bold;';
            nameSpan.innerText = name;
            
            const inviteBtn = document.createElement('button');
            inviteBtn.style.cssText = 'background: rgba(0,255,0,0.1); border: 1px solid #00ff00; color: #00ff00; font-size: 8px; padding: 2px 8px; cursor: pointer; font-family: "Orbitron"; border-radius: 2px;';
            inviteBtn.innerText = 'INVITAR';
            inviteBtn.onclick = () => this.invite(name);
            
            row.appendChild(nameSpan);
            row.appendChild(inviteBtn);
            list.appendChild(row);
        });
    }

    renderTab() {
        const list = document.getElementById('party-list');
        if (!list) return;
        list.innerHTML = '';
        const btn = document.getElementById('leave-party-btn');
        const party = this.scene.currentParty;

        if (!party || !party.members || party.members.length === 0) {
            list.innerHTML = '<div style="color: #666; font-style: italic; text-align: center; margin-top: 50px;">No estás en ningún grupo actualmente.</div>';
            if (btn) btn.style.display = 'none';
            return;
        }

        if (btn) btn.style.display = 'block';
        party.names.forEach((name, i) => {
            const row = document.createElement('div');
            row.style.cssText = 'display: flex; justify-content: space-between; align-items: center; padding: 10px; background: rgba(0,255,255,0.1); border: 1px solid rgba(0,255,255,0.3); border-radius: 4px;';
            
            const nameSpan = document.createElement('span');
            nameSpan.style.cssText = 'color: white; font-family: "Outfit";';
            nameSpan.innerText = (i === 0 ? '👑 ' : '👤 ') + name;
            
            const statusSpan = document.createElement('span');
            statusSpan.style.cssText = 'color: #00ff00; font-size: 10px; font-family: "Orbitron";';
            statusSpan.innerText = 'CONECTADO';
            
            row.appendChild(nameSpan);
            row.appendChild(statusSpan);
            list.appendChild(row);
        });
    }

    updateHUD() {
        const party = this.scene.currentParty;
        const hudContainer = document.getElementById('party-hud');
        const hudList = document.getElementById('party-hud-list');
        
        if (!party || !party.members || party.members.length <= 1) {
            if (hudContainer) hudContainer.style.display = 'none';
            return;
        }

        if (hudContainer) hudContainer.style.display = 'flex';
        if (!hudList) return;

        const socketId = this.scene.socketManager.socket.id;

        party.members.forEach((id, index) => {
            const name = party.names[index];
            let hp = 0, maxHp = 1, shield = 0, maxShield = 1;

            if (id === this.player?.id || id === socketId) {
                hp = this.player?.hp || 0; 
                maxHp = this.player?.maxHp || 2000;
                shield = this.player?.shield || 0; 
                maxShield = this.player?.maxShield || 1000;
            } else {
                let rp = this.scene.entities.remotePlayers.get(id); // Buscar por ID (dbId o sid)
                
                // Fallback: Triple Match v141.61
                if (!rp) {
                    for (const p of this.scene.entities.remotePlayers.values()) {
                        if (p.dbId === id || p.sid === id || p.id === id || (p.user && p.user.toLowerCase() === name.toLowerCase())) { 
                            rp = p; break;
                        }
                    }
                }

                if (rp) {
                    hp = rp.hp || 0; maxHp = rp.maxHp || 2000;
                    shield = rp.shield || 0; maxShield = rp.maxShield || 1000;
                }
            }

            const hpPct = Math.max(0, (hp / (maxHp || 1)) * 100);
            const shPct = Math.max(0, (shield / (maxShield || 1)) * 100);

            let rowId = `party-row-${id}`;
            let row = document.getElementById(rowId);
            if (!row) {
                row = document.createElement('div');
                row.id = rowId;
                row.className = 'party-member-row';
                hudList.appendChild(row);
            }

            row.innerHTML = `
                <div class="party-name">${id === this.player.id ? '👑 ' : ''}${name}</div>
                <div class="party-hp-bar"><div class="party-hp-fill" style="width: ${hpPct}%"></div></div>
                <div class="party-sh-bar"><div class="party-sh-fill" style="width: ${shPct}%"></div></div>
                <div class="party-stats-num"><span>HP: ${Math.ceil(hp)}</span><span>SH: ${Math.ceil(shield)}</span></div>
            `;
        });

        Array.from(hudList.children).forEach(child => {
            const mid = child.id.replace('party-row-', '');
            if (!party.members.includes(mid)) child.remove();
        });
    }
}
