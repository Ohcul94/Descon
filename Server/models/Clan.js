const mongoose = require('mongoose');

const ClanSchema = new mongoose.Schema({
    name: { type: String, required: true, unique: true, index: true },
    tag: { type: String, required: true, unique: true, uppercase: true, maxlength: 4 },
    leader: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    members: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
    description: { type: String, default: "Flota estelar en expansión." },
    joinType: { type: String, enum: ['open', 'invite'], default: 'open' },
    maxMembers: { type: Number, default: 20 },
    requests: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
    sentInvites: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }], // v244.99: Seguimiento de invitaciones enviadas
    hubs: { type: Number, default: 0 },
    createdAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('Clan', ClanSchema);
