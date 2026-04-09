require('dotenv').config();
const mongoose = require('mongoose');
const bcrypt = require('bcrypt');
const User = require('./server/models/User');

async function migrate() {
    try {
        console.log("Conectando a MongoDB para migración...");
        await mongoose.connect(process.env.MONGODB_URI);
        
        const users = await User.find({});
        console.log(`Encontrados ${users.length} usuarios. Iniciando blindaje...`);

        let migratedCount = 0;
        for (let user of users) {
            // Si la contraseña ya está hasheada (empieza por $2b$), la salteamos
            if (user.password.startsWith('$2b$')) {
                console.log(`- [${user.username}] ya está blindada. Salteada.`);
                continue;
            }

            // Hashear la contraseña vieja
            console.log(`- Blindando cuenta: [${user.username}]...`);
            user.password = await bcrypt.hash(user.password, 10);
            await user.save();
            migratedCount++;
        }

        console.log(`\n¡MIGRACIÓN COMPLETADA! ${migratedCount} cuentas blindadas con éxito.`);
        process.exit(0);

    } catch (err) {
        console.error("Error en la migración:", err);
        process.exit(1);
    }
}

migrate();
