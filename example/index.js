const { setUp, showNotification } = require("./build/MyExample.node");

exports.setUp = () => { 
    setUp();
};

exports.showNotification = (id, title, body, containsCall, action) => { 
    const notificationId = showNotification(id, title, body, containsCall, action);
    return notificationId
};
