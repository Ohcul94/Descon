const mongoose = require('mongoose');

// v500.0: MERCADO / CASA DE SUBASTAS - Publicaciones de jugadores
const MarketListingSchema = new mongoose.Schema({
    sellerId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    sellerName: { type: String, required: true },
    item: { type: Object, required: true },
    price: { type: Number, required: true },
    currency: { type: String, enum: ['hubs', 'ohcu'], required: true },
    amount: { type: Number, default: 1 },
    status: { type: String, enum: ['active', 'sold', 'expired', 'cancelled'], default: 'active', index: true },
    listedAt: { type: Date, default: Date.now },
    expiresAt: { type: Date, required: true, index: true },
    soldAt: { type: Date, default: null },
    buyerId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null }
});

MarketListingSchema.index({ status: 1, expiresAt: 1 });
MarketListingSchema.index({ sellerId: 1, status: 1 });

module.exports = mongoose.model('MarketListing', MarketListingSchema);