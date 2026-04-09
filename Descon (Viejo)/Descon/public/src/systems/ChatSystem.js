export default class ChatSystem {
    constructor(scene) {
        this.scene = scene;
        
        this.chatInput = document.getElementById('chat-input');
        this.chatInputWrapper = document.getElementById('chat-input-wrapper');
        this.chatContainer = document.getElementById('chat-container');
        this.chatMessages = document.getElementById('chat-messages');
        this.chatChannel = document.getElementById('chat-channel-select');

        this.init();
    }

    get player() { return this.scene.player; }

    init() {
        if (!this.chatInput) return;
        
        // CLICK TO FOCUS (Móvil v66.4)
        this.chatMessages.onclick = (e) => {
            e.stopPropagation();
            this.focus();
        };

        const sendBtn = document.getElementById('chat-send-btn');
        if (sendBtn) {
            sendBtn.onclick = (e) => {
                e.stopPropagation();
                this.send();
            };
        }

        window.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                if (document.activeElement === this.chatInput) {
                    this.send();
                } else {
                    this.focus();
                }
            }
        });

        const checkSocket = () => {
            if (this.scene.socketManager && this.scene.socketManager.socket) {
                this.setupSocketEvents();
            } else {
                setTimeout(checkSocket, 100);
            }
        };
        checkSocket();
    }

    setupSocketEvents() {
        this.scene.socketManager.socket.on('chatMessage', (data) => {
            this.addMessage(data);
            
            // v142.61: Detección Universal de Remitente (Socket o DB)
            const socketId = this.scene.socketManager.socket.id;
            if (data.senderId === socketId || data.sender === this.player?.userData?.user) {
                this.player?.showChatBubble(data.msg);
            } else {
                const remote = this.scene.entities.remotePlayers.get(data.senderId);
                if (remote) remote.showChatBubble(data.msg);
            }
        });
    }

    focus() {
        if (this.chatContainer.classList.contains('minimized')) {
            window.toggleHUDElement('chat');
        }
        this.chatContainer.classList.add('active');
        this.chatInputWrapper.style.display = 'flex';
        this.chatInput.focus();
    }

    send() {
        if (!this.chatInput) return;
        const msg = this.chatInput.value.trim();
        const channel = this.chatChannel.value;
        if (msg.length > 0) {
            this.scene.socketManager.socket.emit('chatMessage', {
                msg: msg.substring(0, 50),
                channel: channel
            });
        }
        this.chatInput.value = '';
        this.chatInput.blur();
        this.chatInputWrapper.style.display = 'none';
        this.chatContainer.classList.remove('active');
    }

    addMessage(data) {
        const msgDiv = document.createElement('div');
        msgDiv.className = 'chat-msg';
        
        const channelSpan = document.createElement('span');
        channelSpan.className = `channel channel-${data.channel}`;
        channelSpan.textContent = data.channel.toUpperCase();
        
        const senderSpan = document.createElement('span');
        senderSpan.className = 'sender';
        senderSpan.textContent = data.sender + ':';
        
        const textSpan = document.createElement('span');
        textSpan.textContent = data.msg;
        
        msgDiv.appendChild(channelSpan);
        msgDiv.appendChild(senderSpan);
        msgDiv.appendChild(textSpan);
        
        this.chatMessages.appendChild(msgDiv);
        this.chatMessages.scrollTop = this.chatMessages.scrollHeight;
        
        if (this.chatMessages.childElementCount > 30) {
            this.chatMessages.removeChild(this.chatMessages.firstChild);
        }
    }
}
