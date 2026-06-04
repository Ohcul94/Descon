const mongoose = require('mongoose');

const sessionSchema = new mongoose.Schema({
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    username: { type: String, required: true },
    ip: { type: String, required: true },
    loginAt: { type: Date, default: Date.now },
    logoutAt: { type: Date },
    durationMinutes: { type: Number, default: 0 },
    zoneAtLogout: { type: Number },
    levelAtLogout: { type: Number }
}, { timestamps: true });

// Índice para búsquedas rápidas por usuario
sessionSchema.index({ username: 1, loginAt: -1 });

module.exports = mongoose.model('Session', sessionSchema);
