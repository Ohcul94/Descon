export default class TalentSystem {
    constructor(scene) {
        this.scene = scene;
        window.resetSkills = () => this.handleReset();
        // v147.72: Restauración Profesional de la Red de 24 Talentos (3x8)
        this.skillData = [
            // INGENIERÍA (Azul/Cian) - 8 Talentos
            { id: 'eng_1', category: 'engineering', name: 'REFUERZO DE CASCO', desc: '+2% HP por nivel', max: 5 },
            { id: 'eng_2', category: 'engineering', name: 'ESCUDO DINÁMICO', desc: '+2% Escudo por nivel', max: 5 },
            { id: 'eng_3', category: 'engineering', name: 'REGEN EMERGENGIA', desc: '+5% HP Reparación', max: 5 },
            { id: 'eng_4', category: 'engineering', name: 'CAPACITOR OHCU', desc: '+5% Shield Regen', max: 5 },
            { id: 'eng_5', category: 'engineering', name: 'PLACAS NANOBOTS', desc: '+1% Armadura total', max: 5 },
            { id: 'eng_6', category: 'engineering', name: 'REACTOR FUSIÓN', desc: '+3% Eficiencia Energía', max: 5 },
            { id: 'eng_7', category: 'engineering', name: 'MANTE GALÁCTICO', desc: '-5% Costo Reparación', max: 5 },
            { id: 'eng_8', category: 'engineering', name: 'ESTABL FLOTANTE', desc: '+1% Estabilidad (Vel)', max: 5 },

            // COMBATE (Rojo) - 8 Talentos
            { id: 'com_1', category: 'combat', name: 'LÁSER SOBRECARGA', desc: '+3% Daño Láser', max: 5 },
            { id: 'com_2', category: 'combat', name: 'MIRILLA TÁCTICA', desc: '+2% Prob. Crítico', max: 5 },
            { id: 'com_3', category: 'combat', name: 'FURIA DEL PILOTO', desc: '+5% Daño Crítico', max: 5 },
            { id: 'com_4', category: 'combat', name: 'CARGA PROYECTIL', desc: '+5% Bonus Munición', max: 5 },
            { id: 'com_5', category: 'combat', name: 'DISPARO PRECISIÓN', desc: '+2% Puntería', max: 5 },
            { id: 'com_6', category: 'combat', name: 'PERFORACIÓN TÉRM', desc: '+3% Ignorar Escudo', max: 5 },
            { id: 'com_7', category: 'combat', name: 'CADENCIA MILITAR', desc: '-2% CD de Disparo', max: 5 },
            { id: 'com_8', category: 'combat', name: 'BLINDAJE ATAQUE', desc: '+1% Evasión en Combate', max: 5 },

            // CIENCIA (Violeta) - 8 Talentos
            { id: 'sci_1', category: 'science', name: 'MOTORES FUSIÓN', desc: '+1.5% Velocidad Base', max: 5 },
            { id: 'sci_2', category: 'science', name: 'ESCÁNER TÁCTICO', desc: '+10% Rango Minimapa', max: 5 },
            { id: 'sci_3', category: 'science', name: 'MINERÍA OHCU', desc: '+5% OHCU de Kills', max: 5 },
            { id: 'sci_4', category: 'science', name: 'MERCADO GALÁXIA', desc: '-2% Descuento Tienda', max: 5 },
            { id: 'sci_5', category: 'science', name: 'ENFRIAMIENTO RÁP', desc: '-3% CD Habilidades', max: 5 },
            { id: 'sci_6', category: 'science', name: 'SINCRONÍA TACT', desc: '+1% Bonus en Grupo', max: 5 },
            { id: 'sci_7', category: 'science', name: 'SENSORES PRECI', desc: '+5% Loot de Bosses', max: 5 },
            { id: 'sci_8', category: 'science', name: 'SALTO HIPERESP', desc: '+10% Distancia Dash', max: 5 }
        ];
    }

    get player() { return this.scene.player; }

    render() {
        const container = document.getElementById('skill-tree-container');
        const pointsVal = document.getElementById('skill-points-val');
        if (!container || !this.player) return;

        pointsVal.innerText = this.player.skillPoints || 0;
        container.innerHTML = '';

        // v147.72: Renderizado en 3 Columnas Estilo Pro (8 por Rama)
        const categories = { 
            engineering: { name: 'INGENIERÍA', class: 'branch-eng' },
            combat: { name: 'COMBATE', class: 'branch-com' },
            science: { name: 'CIENCIA', class: 'branch-sci' }
        };

        Object.keys(categories).forEach(catKey => {
            const branch = document.createElement('div');
            branch.className = `skill-branch ${categories[catKey].class}`;
            branch.innerHTML = `<h3 style="color:#fff; font-size:12px; margin-bottom:15px; border-bottom:1px solid rgba(255,255,255,0.1); padding-bottom:5px;">${categories[catKey].name}</h3>`;
            
            const skillsInCat = this.skillData.filter(s => s.category === catKey);
            skillsInCat.forEach((skill, idx) => {
                const level = (this.player.skillTree && this.player.skillTree[catKey]) ? this.player.skillTree[catKey][idx] || 0 : 0;
                
                const node = document.createElement('div');
                node.className = 'skill-node' + (level > 0 ? ' active' : '');
                if (level === skill.max) node.className += ' maxed';

                node.innerHTML = `
                    <div class="skill-info">
                        <div class="skill-name">${skill.name}</div>
                        <div class="skill-desc">${skill.desc}</div>
                        <div class="skill-level-dots">
                            ${Array.from({length: skill.max}, (_, i) => `<div class="skill-dot ${i < level ? 'active' : ''}"></div>`).join('')}
                        </div>
                    </div>
                `;

                node.onclick = () => this.investPoint(skill);
                branch.appendChild(node);
            });
            container.appendChild(branch);
        });
    }

    investPoint(skill) {
        if (!this.player || this.player.skillPoints <= 0) {
            if (window.hudNotify) window.hudNotify("SIN PUNTOS DISPONIBLES", 'warn');
            return;
        }

        const skillsInCat = this.skillData.filter(s => s.category === skill.category);
        const relativeIdx = skillsInCat.indexOf(skill);
        const currentLevel = (this.player.skillTree && this.player.skillTree[skill.category]) ? this.player.skillTree[skill.category][relativeIdx] || 0 : 0;

        if (currentLevel < skill.max) {
            this.player.skillPoints--;
            if (!this.player.skillTree[skill.category]) this.player.skillTree[skill.category] = [0,0,0,0,0,0,0,0];
            this.player.skillTree[skill.category][relativeIdx]++;
            
            this.player.updateStats(this.scene.currentShipModel, this.player.equipped);
            this.render();
            if (this.scene.saveProgress) this.scene.saveProgress();
            if (window.hudNotify) window.hudNotify(`${skill.name} MEJORADO`, 'success');
        }
    }

    handleReset() {
        if (!this.player) return;
        const RESET_COST = 5000;

        if (this.player.ohcu < RESET_COST) {
            if (window.hudNotify) window.hudNotify(`OHCU INSUFICIENTE (NECESITAS ${RESET_COST})`, 'warn');
            return;
        }

        const totalInvested = Object.values(this.player.skillTree).reduce((total, branch) => {
            return total + branch.reduce((a, b) => a + b, 0);
        }, 0);

        if (totalInvested <= 0) {
            if (window.hudNotify) window.hudNotify("NO HAY PUNTOS INVERTIDOS", 'info');
            return;
        }

        const details = `¿RESETEAR LOS 24 TALENTOS?<br><span style="color:#ff3333">COSTO: ${RESET_COST} OHCU</span><br>RECUPERARÁS ${totalInvested} PUNTOS.`;
        
        if (window.openConfirmModal) {
            window.openConfirmModal(details, () => {
                this.player.ohcu -= RESET_COST;
                this.player.skillPoints += totalInvested;
                this.player.skillTree = {
                    engineering: [0,0,0,0,0,0,0,0],
                    combat: [0,0,0,0,0,0,0,0],
                    science: [0,0,0,0,0,0,0,0]
                };
                
                this.player.updateStats(this.scene.currentShipModel, this.player.equipped);
                this.render();
                if (this.scene.saveProgress) this.scene.saveProgress();
                if (window.hudNotify) window.hudNotify("¡PUNTOS DE TALENTO RESETEADOS!", 'success');
            }, 'SISTEMA DE REESTRUCTURACIÓN');
        }
    }
}
