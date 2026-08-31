require('dotenv').config();
const mongoose = require('mongoose');
const bcrypt = require('bcrypt');
const User = require('../models/User');

// Toma el primer administrador configurado en el archivo .env o usa caelli94 por defecto
const username = (process.env.ADMIN_USERNAMES || 'caelli94').split(',')[0].trim().toLowerCase();

async function run() {
    const newPassword = process.argv[2];
    if (!newPassword) {
        console.error("Uso: npm run change-password <nueva_contraseña>");
        process.exit(1);
    }

    if (!process.env.MONGODB_URI) {
        console.error("Error: MONGODB_URI no está definido en el archivo .env");
        process.exit(1);
    }

    try {
        console.log(`Conectando a MongoDB para actualizar contraseña del admin: ${username}...`);
        // Usar la URI y configuraciones de pool estándar
        await mongoose.connect(process.env.MONGODB_URI);
        
        const user = await User.findOne({ username: username });
        const hashedPassword = await bcrypt.hash(newPassword, 10);

        if (!user) {
            console.log(`El usuario admin '${username}' no existe. Creando nuevo usuario administrador...`);
            const newUser = new User({
                username: username,
                password: hashedPassword
            });
            await newUser.save();
            console.log(`¡Administrador '${username}' creado con éxito en la base de datos!`);
        } else {
            user.password = hashedPassword;
            await user.save();
            console.log(`¡Contraseña del administrador '${username}' actualizada con éxito!`);
        }
    } catch (error) {
        console.error("Error al actualizar la contraseña:", error);
    } finally {
        await mongoose.disconnect();
        process.exit(0);
    }
}

run();
