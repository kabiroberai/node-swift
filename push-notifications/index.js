const { setUp, showNotification } = require("./build/AmiePushNotifications.node");

exports.setUp = () => { 
    setUp();
};

exports.showNotification = (id, title, body, actions, onAction) => { 
    const notificationId = showNotification(id, title, body, actions, onAction);
    return notificationId
};
