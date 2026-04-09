const mongoose = require('mongoose');
const User = require('./server/models/User');
require('dotenv').config();

async function inject() {
    try {
        console.log("Conectando a MongoDB...");
        await mongoose.connect(process.env.MONGODB_URI);
        
        const username = 'player3'; 
        const amount = 100000;

        const update = {
            $inc: {
                "gameData.hubs": amount,
                "gameData.ohcu": amount
            }
        };

        const result = await User.updateOne({ username: username.toLowerCase() }, update);

        if (result.matchedCount > 0) {
            console.log(`\n¡ÉXITO GALÁCTICO! Se han inyectado ${amount} HUBS y ${amount} OHCU a la cuenta: ${username}`);
        } else {
            console.log(`\nERROR: No se encontró al piloto [${username}] en la base de datos.`);
        }

    } catch (e) {
        console.error("Error inyectando fondos:", e);
    } finally {
        mongoose.disconnect();
    }
}

inject();
