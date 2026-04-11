const mongoose = require('mongoose');
const User = require('./models/User');

async function check() {
    await mongoose.connect('mongodb+srv://Caelli94:3Im1X26N1hjUGeCj@descon.hqihpo3.mongodb.net/?appName=Descon');
    const user = await User.findOne({ username: 'caelli94' });
    if (user) {
        console.log("Current Ship:", user.gameData.currentShipId);
        console.log("Global Equipped:", JSON.stringify(user.gameData.equipped));
        console.log("Equipped By Ship:", user.gameData.equippedByShip);
    } else {
        console.log("Usuario no encontrado.");
    }
    process.exit();
}

check();
