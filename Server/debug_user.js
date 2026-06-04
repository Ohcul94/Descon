require('dotenv').config();
const mongoose = require('mongoose');
const User = require('./models/User');

async function resetUser() {
    try {
        console.log("Conectando a MongoDB...");
        await mongoose.connect(process.env.MONGODB_URI);
        console.log("Conectado con éxito.");

        const user = await User.findOne({ username: { $regex: new RegExp("^caelli94$", "i") } });
        if (!user) {
            console.log("Usuario Caelli94 no encontrado.");
            mongoose.disconnect();
            return;
        }

        console.log("Restaurando naves y fondos de caelli94...");
        
        user.gameData.currentShipId = 6;
        user.gameData.ownedShips = [1, 2, 3, 4, 5, 6];
        user.gameData.zone = 1;
        user.gameData.lastPos = { x: 2000, y: 2000 };
        user.gameData.hp = 3200;
        user.gameData.shield = 3200;
        user.gameData.hubs = 1000000;
        user.gameData.ohcu = 100000;
        user.gameData.inventory = [];
        user.gameData.equipped = { w: [], s: [], e: [], x: [] };
        
        // Reset de equippedByShip a estructura vacía para todas las naves
        user.gameData.equippedByShip = {
            "1": { w: [], s: [], e: [], x: [] },
            "2": { w: [], s: [], e: [], x: [] },
            "3": { w: [], s: [], e: [], x: [] },
            "4": { w: [], s: [], e: [], x: [] },
            "5": { w: [], s: [], e: [], x: [] },
            "6": { w: [], s: [], e: [], x: [] }
        };

        user.markModified('gameData');
        await user.save();
        
        console.log("¡Naves y fondos de Caelli94 restaurados exitosamente!");
        mongoose.disconnect();
    } catch (e) {
        console.error("Error restaurando usuario:", e);
        mongoose.disconnect();
    }
}

resetUser();
