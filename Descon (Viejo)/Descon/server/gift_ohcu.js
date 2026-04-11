const mongoose = require('mongoose');
const User = require('./models/User');

async function gift() {
    await mongoose.connect('mongodb://127.0.0.1:27017/galactic_mmo');
    const user = await User.findOne({ username: 'Caelli94' });
    if (user) {
        user.gameData.ohcu += 200000;
        await user.save();
        console.log("¡Compensación entregada! 200,000 OHCU acreditados a Caelli94.");
    } else {
        console.log("Usuario Caelli94 no encontrado.");
    }
    process.exit();
}

gift();
