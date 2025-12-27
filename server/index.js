
require("dotenv").config();
const { Server } = require("socket.io");

const port = process.env.PORT || 3000;
const apiKey = process.env.API_KEY;

const io = new Server(port, {
  cors: {
    origin: "*",
  },
});

console.log(`Signaling server running on port ${port}`);

// Authentication Middleware
io.use((socket, next) => {
  const token = socket.handshake.auth.token;
  if (token === apiKey) {
    next();
  } else {
    next(new Error("unauthorized"));
  }
});

// Initialize Firebase Admin
let admin;
try {
  const fs = require('fs');
  // Check for Render secret file path first, then local
  const renderPath = "/etc/secrets/serviceAccountKey.json";
  const localPath = "./serviceAccountKey.json";

  const serviceAccountPath = fs.existsSync(renderPath) ? renderPath : localPath;

  if (fs.existsSync(serviceAccountPath)) {
    const serviceAccount = require(serviceAccountPath);
    admin = require("firebase-admin");
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    console.log(`Firebase Admin Initialized (using ${serviceAccountPath})`);
  } else {
    console.warn("Service Account Key not found at /etc/secrets/ or ./");
  }

} catch (e) {
  console.warn("Firebase Admin Initialization Failed:", e.message);
}

// Track persistent users: { username: { socketId, fcmToken, online } }
const users = new Map();

io.on("connection", (socket) => {
  console.log("User connected:", socket.id);
  let currentUsername = null;

  socket.on("login", (username) => {
    currentUsername = username;

    // Get existing data or create new
    const userData = users.get(username) || { fcmToken: null };
    userData.socketId = socket.id;
    userData.online = true;
    users.set(username, userData);

    console.log(`User registered: ${username} (${socket.id})`);

    // Broadcast updated user list
    broadcastUserList();
  });

  socket.on("store-fcm-token", (token) => {
    if (currentUsername) {
      const userData = users.get(currentUsername);
      if (userData) {
        userData.fcmToken = token;
        users.set(currentUsername, userData);
        console.log(`Stored FCM token for ${currentUsername}`);
      }
    }
  });

  socket.on("disconnect", () => {
    console.log("User disconnected:", socket.id);
    if (currentUsername && users.has(currentUsername)) {
      const userData = users.get(currentUsername);
      userData.online = false;
      userData.socketId = null;
      users.set(currentUsername, userData);
    }
    broadcastUserList();
  });

  socket.on("offer", async (payload) => {
    // payload: { targetUsername, sdp, type, ... } 
    // Note: target is now USERNAME, not socketId
    const targetUser = users.get(payload.target);

    if (targetUser) {
      // 1. Try to send via Socket if online
      if (targetUser.online && targetUser.socketId) {
        io.to(targetUser.socketId).emit("offer", {
          ...payload,
          sender: currentUsername, // Send username as sender
        });
      }

      // 2. Always send Push (or if offline)
      // We send it to ensure wake-up or heads-up
      if (targetUser.fcmToken && admin) {
        console.log(`Sending Push Notification to ${payload.target}`);
        try {
          // Generate a valid UUID for the call (CallKit requires this)
          const callUuid = require('uuid').v4();

          await admin.messaging().send({
            token: targetUser.fcmToken,
            data: {
              type: 'offer',
              target: payload.target,
              sender: currentUsername || "Unknown",
              sdp: typeof payload.sdp === 'string' ? payload.sdp : JSON.stringify(payload.sdp),
              type_val: payload.type || 'offer',
              uuid: callUuid, // USE VALID UUID!
              nameCaller: currentUsername || "Unknown",
              appName: "AnyTalk",
              handle: currentUsername || "Unknown",
              avatar: "https://i.pravatar.cc/100",
            },
            android: { priority: 'high', ttl: 0 },
            apns: {
              payload: { aps: { contentAvailable: true } },
              headers: { "apns-push-type": "background", "apns-priority": "5", "apns-topic": "com.anytalk.client" }
            }
          });
          console.log(`Push sent successfully (UUID: ${callUuid})`);
        } catch (e) {
          console.error("Error sending push:", e);
        }
      }
    } else {
      console.log(`Target user ${payload.target} not found`);
    }
  });

  socket.on("answer", (payload) => {
    // payload.target is now USERNAME
    const targetUser = users.get(payload.target);
    if (targetUser && targetUser.online && targetUser.socketId) {
      io.to(targetUser.socketId).emit("answer", {
        ...payload,
        sender: currentUsername
      });
    }
  });

  socket.on("ice-candidate", (incoming) => {
    const targetUser = users.get(incoming.target);
    if (targetUser && targetUser.online && targetUser.socketId) {
      io.to(targetUser.socketId).emit("ice-candidate", {
        ...incoming.candidate,
        sender: currentUsername
      });
    }
  });

  socket.on("end-call", (payload) => {
    const targetUser = users.get(payload.target);
    if (targetUser && targetUser.online && targetUser.socketId) {
      io.to(targetUser.socketId).emit("end-call", {
        ...payload,
        sender: currentUsername
      });
    }
  });

  socket.on("get-ice-servers", async (callback) => {
    const iceServers = [
      { urls: "stun:stun.l.google.com:19302" },
    ];

    // Cloudflare TURN logic
    if (process.env.CLOUDFLARE_TURN_KEY_ID && process.env.CLOUDFLARE_API_TOKEN) {
      try {
        const keyId = process.env.CLOUDFLARE_TURN_KEY_ID;
        const token = process.env.CLOUDFLARE_API_TOKEN;

        const response = await fetch(`https://rtc.live.cloudflare.com/v1/turn/keys/${keyId}/credentials/generate`, {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${token}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            ttl: 86400 // 24 hours
          })
        });

        if (response.ok) {
          const data = await response.json();
          // Cloudflare returns { iceServers: { urls, username, credential } }
          // We need to push the server object correctly
          if (data.iceServers) {
            iceServers.push(data.iceServers);
            console.log("Generated Cloudflare TURN credentials");
          }
        } else {
          console.error("Failed to generate Cloudflare credentials:", await response.text());
        }
      } catch (e) {
        console.error("Error fetching Cloudflare credentials:", e);
      }
    }
    // Fallback to static if Cloudflare not configured but old TURN vars exist
    else if (process.env.TURN_URL && process.env.TURN_USERNAME && process.env.TURN_PASSWORD) {
      iceServers.push({
        urls: process.env.TURN_URL,
        username: process.env.TURN_USERNAME,
        credential: process.env.TURN_PASSWORD,
      });
      console.log("Using static TURN credentials");
    }

    callback(iceServers);
  });

  function broadcastUserList() {
    // Send array of { username, online }
    const userList = Array.from(users.entries()).map(([username, data]) => ({
      username,
      online: data.online
    }));
    io.emit("update-user-list", userList);
  }
});
