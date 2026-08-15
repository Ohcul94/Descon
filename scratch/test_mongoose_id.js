const mongoose = require('mongoose');
const testIdStr = "64dc9335a9602e1c94a9e52d"; // ID típico de 24 hex de Mongo
console.log("Is valid string ID:", mongoose.Types.ObjectId.isValid(testIdStr));
