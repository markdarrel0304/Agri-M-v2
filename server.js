import express from "express";
import mysql from "mysql2";
import cors from "cors";
import bcrypt from "bcrypt";
import jwt from "jsonwebtoken";
import multer from "multer";
import path from "path";
import { fileURLToPath } from "url";
import fs from "fs";
import speakeasy from 'speakeasy';
import QRCode from 'qrcode';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = 8881;
const SECRET_KEY = "your_jwt_secret_change_this_in_production";

app.use(cors());
app.use(express.json());

// Create uploads directory
const uploadsDir = path.join(__dirname, 'uploads');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir);
  console.log('📁 Created uploads directory');
}

app.use('/uploads', express.static(uploadsDir));

// Configure multer
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadsDir),
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, uniqueSuffix + path.extname(file.originalname));
  }
});

const upload = multer({ 
  storage: storage,
  limits: { fileSize: 10 * 1024 * 1024 }, // Increased to 10MB
  fileFilter: (req, file, cb) => {
    console.log('📸 File upload attempt:');
    console.log('   Original name:', file.originalname);
    console.log('   Mimetype:', file.mimetype);
    console.log('   Size:', file.size);
    
    // More flexible image validation
    const allowedMimes = [
      'image/jpeg',
      'image/jpg', 
      'image/png',
      'image/gif',
      'image/webp',
      'image/bmp',
      'image/svg+xml'
    ];
    
    const allowedExts = /jpeg|jpg|png|gif|webp|bmp|svg/i;
    const extname = allowedExts.test(path.extname(file.originalname).toLowerCase());
    const mimetype = allowedMimes.includes(file.mimetype.toLowerCase());
    
    console.log('   Extension valid:', extname);
    console.log('   Mimetype valid:', mimetype);
    
    if (mimetype || extname) {
      console.log('✅ File accepted');
      return cb(null, true);
    } else {
      console.log('❌ File rejected - not an image');
      cb(new Error('Only image files are allowed! Received: ' + file.mimetype));
    }
  }
});



// MySQL connection
const db = mysql.createConnection({
  host: "localhost",
  user: "root",
  password: "yourpassword",
  database: "agridb",
});

db.connect((err) => {
  if (err) {
    console.error("❌ MySQL connection failed:", err);
  } else {
    console.log("✅ MySQL connected!");
  }
});

// -------- MIDDLEWARE: CHECK ADMIN STATUS --------
function isAdmin(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: "No token provided." });

  const token = authHeader.split(" ")[1];
  jwt.verify(token, SECRET_KEY, (err, decoded) => {
    if (err) return res.status(401).json({ error: "Invalid token." });

    db.query(
      "SELECT is_admin, email FROM users WHERE id = ?",
      [decoded.id],
      (err, results) => {
        if (err) return res.status(500).json({ error: "Database error." });
        if (results.length === 0) return res.status(404).json({ error: "User not found." });

        const user = results[0];
        // Check if user is admin by is_admin field or specific emails
        if (user.is_admin === 1 || user.email === 'admin@agri.com' || user.email === 'admin@admin.com') {
          req.userId = decoded.id;
          next();
        } else {
          return res.status(403).json({ error: "Admin access required." });
        }
      }
    );
  });
}

// -------- REGISTER --------
app.post("/api/register", async (req, res) => {
  const { username, email, password } = req.body;
  if (!username || !email || !password)
    return res.status(400).json({ error: "All fields are required." });

  try {
    const hashedPassword = await bcrypt.hash(password, 10);
    db.query(
      "INSERT INTO users (username, email, password) VALUES (?, ?, ?)",
      [username, email, hashedPassword],
      (err, result) => {
        if (err) {
          if (err.code === 'ER_DUP_ENTRY') {
            return res.status(400).json({ error: "Email already exists." });
          }
          return res.status(500).json({ error: "Database error." });
        }
        res.json({ message: "User registered successfully." });
      }
    );
  } catch (err) {
    res.status(500).json({ error: "Server error." });
  }
});

// -------- LOGIN --------
app.post("/api/login", (req, res) => {
  const { email, password } = req.body;
  const ipAddress = req.ip || req.connection.remoteAddress || 'Unknown';
  const device = req.headers['user-agent'] || 'Unknown';

  if (!email || !password) {
    return res.status(400).json({ error: "Email and password are required." });
  }

  db.query("SELECT * FROM users WHERE email = ?", [email], async (err, results) => {
    if (err) return res.status(500).json({ error: "Database error." });
    
    if (results.length === 0) {
      // Record failed login - user not found
      recordLogin(null, false, ipAddress, device);
      return res.status(404).json({ error: "User not found." });
    }

    const user = results[0];
    const match = await bcrypt.compare(password, user.password);
    
    if (!match) {
      // Record failed login - wrong password
      recordLogin(user.id, false, ipAddress, device);
      return res.status(401).json({ error: "Invalid password." });
    }

    // ✅ Record successful login HERE
    recordLogin(user.id, true, ipAddress, device);

    const token = jwt.sign({ id: user.id, email: user.email }, SECRET_KEY, { expiresIn: "24h" });

    res.json({
      token,
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        role: user.role || 'buyer',
        is_seller: (user.role === 'seller' && user.is_approved === 1) ? 1 : 0,
        is_approved: user.is_approved || 0,
        is_admin: user.is_admin || 0,
      },
    });
  });
});

// -------- CHECK ADMIN STATUS --------
app.get("/api/check-admin", (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: "No token provided." });

  const token = authHeader.split(" ")[1];
  jwt.verify(token, SECRET_KEY, (err, decoded) => {
    if (err) return res.status(401).json({ error: "Invalid token." });

    db.query(
      "SELECT is_admin, email, role FROM users WHERE id = ?",
      [decoded.id],
      (err, results) => {
        if (err) return res.status(500).json({ error: "Database error." });
        if (results.length === 0) return res.status(404).json({ error: "User not found." });

        const user = results[0];
        // Check if user is admin by is_admin field or specific emails
        const isUserAdmin = user.is_admin === 1 || 
                       user.email === 'admin@agri.com' || 
                       user.email === 'admin@admin.com';

        res.json({ 
          is_admin: isUserAdmin,
          email: user.email,
          role: user.role
        });
      }
    );
  });
});

// -------- CHECK SELLER STATUS --------
app.get("/api/is-approved-seller", (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: "No token provided." });

  const token = authHeader.split(" ")[1];
  jwt.verify(token, SECRET_KEY, (err, decoded) => {
    if (err) return res.status(401).json({ error: "Invalid token." });

    db.query(
      "SELECT role, is_approved FROM users WHERE id = ?",
      [decoded.id],
      (err, results) => {
        if (err) return res.status(500).json({ error: "Database error." });
        if (results.length === 0) return res.status(404).json({ error: "User not found." });

        const user = results[0];
        const isApprovedSeller = user.role === 'seller' && user.is_approved === 1;

        res.json({
          approved: isApprovedSeller,
          is_seller: isApprovedSeller ? 1 : 0,
          role: user.role || 'buyer',
          is_approved: user.is_approved || 0
        });
      }
    );
  });
});

// -------- ADD PRODUCT --------
app.post("/api/add-product", upload.single('image'), (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: "No token provided." });

  const token = authHeader.split(" ")[1];
  jwt.verify(token, SECRET_KEY, (err, decoded) => {
    if (err) return res.status(401).json({ error: "Invalid token." });

    const { name, price, description, category } = req.body;
    let imageUrl = req.body.image;

    if (req.file) {
      imageUrl = `/uploads/${req.file.filename}`;
    }

    if (!name || !price) {
      return res.status(400).json({ error: "Name and price are required." });
    }

    // Check if user is approved seller
    db.query(
      "SELECT role, is_approved FROM users WHERE id = ?",
      [decoded.id],
      (err, userResults) => {
        if (err) return res.status(500).json({ error: "Database error." });
        if (userResults.length === 0) return res.status(404).json({ error: "User not found." });

        const user = userResults[0];
        const isApprovedSeller = user.role === 'seller' && user.is_approved === 1;

        if (!isApprovedSeller) {
          return res.status(403).json({
            message: "Your seller account is not approved yet."
          });
        }

        // Insert product
        db.query(
          "INSERT INTO products (seller_id, name, price, image_url, description, category) VALUES (?, ?, ?, ?, ?, ?)",
          [decoded.id, name, price, imageUrl || null, description || null, category || 'General'],
          (err, result) => {
            if (err) {
              return res.status(500).json({ error: "Failed to add product." });
            }

            res.status(201).json({ 
              message: "Product added successfully!",
              product_id: result.insertId,
              image_url: imageUrl,
              imageUrl: req.body.image,
            });
          }
        );
      }
    );
  });
});

// -------- GET ALL PRODUCTS --------
app.get("/api/products", (req, res) => {
  db.query(
    `SELECT p.*, u.username as seller_name 
     FROM products p 
     LEFT JOIN users u ON p.seller_id = u.id 
     ORDER BY p.created_at DESC`,
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      res.json({ products: results });
    }
  );
});

// -------- GET SELLER'S PRODUCTS --------
app.get("/api/seller/products", (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: "No token provided." });

  const token = authHeader.split(" ")[1];
  jwt.verify(token, SECRET_KEY, (err, decoded) => {
    if (err) return res.status(401).json({ error: "Invalid token." });

    db.query(
      "SELECT * FROM products WHERE seller_id = ? ORDER BY created_at DESC",
      [decoded.id],
      (err, results) => {
        if (err) return res.status(500).json({ error: "Database error." });
        res.json({ products: results });
      }
    );
  });
});

// -------- UPDATE PRODUCT (SELLER) --------
app.put("/api/products/:id", upload.single('image'), (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: "No token provided." });

  const token = authHeader.split(" ")[1];
  jwt.verify(token, SECRET_KEY, (err, decoded) => {
    if (err) return res.status(401).json({ error: "Invalid token." });

    const productId = req.params.id;
    const { name, price, stock, description, category, status } = req.body;
    let imageUrl = req.body.image;

    if (req.file) {
      imageUrl = `/uploads/${req.file.filename}`;
    }

    // Check if product belongs to user
    db.query(
      "SELECT seller_id FROM products WHERE id = ?",
      [productId],
      (err, results) => {
        if (err) return res.status(500).json({ error: "Database error." });
        if (results.length === 0) return res.status(404).json({ error: "Product not found." });
        if (results[0].seller_id !== decoded.id) {
          return res.status(403).json({ error: "Unauthorized." });
        }

        // Build update query dynamically
        let updateFields = [];
        let updateValues = [];

        if (name) {
          updateFields.push("name = ?");
          updateValues.push(name);
        }
        if (price) {
          updateFields.push("price = ?");
          updateValues.push(price);
        }
        if (stock !== undefined) {
          updateFields.push("stock = ?");
          updateValues.push(stock);
        }
        if (description) {
          updateFields.push("description = ?");
          updateValues.push(description);
        }
        if (category) {
          updateFields.push("category = ?");
          updateValues.push(category);
        }
        if (status) {
          updateFields.push("status = ?");
          updateValues.push(status);
        }
        if (imageUrl) {
          updateFields.push("image_url = ?");
          updateValues.push(imageUrl);
        }

        if (updateFields.length === 0) {
          return res.status(400).json({ error: "No fields to update." });
        }

        updateValues.push(productId);

        db.query(
          `UPDATE products SET ${updateFields.join(", ")} WHERE id = ?`,
          updateValues,
          (err) => {
            if (err) return res.status(500).json({ error: "Failed to update product." });
            res.json({ message: "Product updated successfully!" });
          }
        );
      }
    );
  });
});

// -------- DELETE PRODUCT --------
app.delete("/api/products/:id", (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: "No token provided." });

  const token = authHeader.split(" ")[1];
  jwt.verify(token, SECRET_KEY, (err, decoded) => {
    if (err) return res.status(401).json({ error: "Invalid token." });

    const productId = req.params.id;

    // Check if product belongs to user
    db.query(
      "DELETE FROM products WHERE id = ? AND seller_id = ?",
      [productId, decoded.id],
      (err, result) => {
        if (err) return res.status(500).json({ error: "Database error." });
        if (result.affectedRows === 0) {
          return res.status(404).json({ error: "Product not found or unauthorized." });
        }
        res.json({ message: "Product deleted successfully." });
      }
    );
  });
});

// -------- CREATE ORDER --------
app.post("/api/orders", (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: "No token provided." });

  const token = authHeader.split(" ")[1];
  jwt.verify(token, SECRET_KEY, (err, decoded) => {
    if (err) return res.status(401).json({ error: "Invalid token." });

    const { product_id, product_name, quantity, price } = req.body;

    if (!product_id || !product_name || !quantity || !price) {
      return res.status(400).json({ error: "All fields are required." });
    }

    db.query(
      "INSERT INTO orders (user_id, product_name, quantity, price, status) VALUES (?, ?, ?, ?, 'Pending')",
      [decoded.id, product_name, quantity, price],
      (err, result) => {
        if (err) return res.status(500).json({ error: "Database error." });
        res.status(201).json({ 
          message: "Order placed successfully!",
          order_id: result.insertId 
        });
      }
    );
  });
});

// -------- GET USER ORDERS --------
app.get("/api/orders", (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: "No token provided." });

  const token = authHeader.split(" ")[1];
  jwt.verify(token, SECRET_KEY, (err, decoded) => {
    if (err) return res.status(401).json({ error: "Invalid token." });

    db.query(
      "SELECT * FROM orders WHERE user_id = ? ORDER BY created_at DESC",
      [decoded.id],
      (err, results) => {
        if (err) return res.status(500).json({ error: "Database error." });
        res.json({ orders: results });
      }
    );
  });
});

// -------- GET DASHBOARD STATS --------
// -------- GET DASHBOARD STATS (FIXED) --------
app.get("/api/dashboard-stats", (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: "No token provided." });

  const token = authHeader.split(" ")[1];
  jwt.verify(token, SECRET_KEY, (err, decoded) => {
    if (err) return res.status(401).json({ error: "Invalid token." });

    // First, check if user is a seller
    db.query(
      "SELECT role, is_approved FROM users WHERE id = ?",
      [decoded.id],
      (err, userResults) => {
        if (err) return res.status(500).json({ error: "Database error." });
        if (userResults.length === 0) return res.status(404).json({ error: "User not found." });

        const user = userResults[0];
        const isApprovedSeller = user.role === 'seller' && user.is_approved === 1;

        if (isApprovedSeller) {
          // ✅ SELLER STATS: Show their sales performance
          const sellerStatsQuery = `
            SELECT 
              -- Total COMPLETED sales (as seller)
              (SELECT COUNT(*) 
               FROM orders 
               WHERE seller_id = ? 
               AND status = 'Completed') AS total_orders,
              
              -- Revenue from completed sales
              (SELECT IFNULL(SUM(price * quantity), 0) 
               FROM orders 
               WHERE seller_id = ? 
               AND status = 'Completed') AS total_revenue,
              
              -- Products listed by this seller
              (SELECT COUNT(*) 
               FROM products 
               WHERE seller_id = ?) AS total_products,
              
              -- Additional seller metrics
              (SELECT COUNT(*) 
               FROM orders 
               WHERE seller_id = ? 
               AND status = 'Pending') AS pending_orders,
              
              (SELECT COUNT(*) 
               FROM orders 
               WHERE seller_id = ? 
               AND status IN ('Accepted', 'Confirmed', 'Shipped')) AS active_orders
          `;

          db.query(
            sellerStatsQuery, 
            [decoded.id, decoded.id, decoded.id, decoded.id, decoded.id], 
            (err, results) => {
              if (err) {
                console.log('❌ Seller dashboard stats error:', err);
                return res.status(500).json({ error: "Database error." });
              }
              
              console.log('📊 Seller Dashboard Stats for User:', decoded.id);
              console.log('  Completed Sales:', results[0].total_orders);
              console.log('  Total Revenue:', results[0].total_revenue);
              console.log('  Products Listed:', results[0].total_products);
              console.log('  Pending Orders:', results[0].pending_orders);
              console.log('  Active Orders:', results[0].active_orders);
              
              res.json({
                total_orders: results[0].total_orders || 0,
                total_revenue: parseFloat(results[0].total_revenue) || 0.0,
                total_products: results[0].total_products || 0,
                pending_orders: results[0].pending_orders || 0,
                active_orders: results[0].active_orders || 0,
                user_type: 'seller'
              });
            }
          );
        } else {
          // ✅ BUYER STATS: Show their purchase history
          const buyerStatsQuery = `
            SELECT 
              -- Total orders placed as buyer
              (SELECT COUNT(*) 
               FROM orders 
               WHERE user_id = ?) AS total_orders,
              
              -- Total amount spent
              (SELECT IFNULL(SUM(price * quantity), 0) 
               FROM orders 
               WHERE user_id = ? 
               AND status IN ('Completed', 'Shipped', 'Accepted', 'Pending')) AS total_spent,
              
              -- Total products available in marketplace
              (SELECT COUNT(*) 
               FROM products 
               WHERE status = 'available') AS total_products,
              
              -- Pending orders
              (SELECT COUNT(*) 
               FROM orders 
               WHERE user_id = ? 
               AND status = 'Pending') AS pending_orders,
              
              -- Completed orders
              (SELECT COUNT(*) 
               FROM orders 
               WHERE user_id = ? 
               AND status = 'Completed') AS completed_orders
          `;

          db.query(
            buyerStatsQuery, 
            [decoded.id, decoded.id, decoded.id, decoded.id], 
            (err, results) => {
              if (err) {
                console.log('❌ Buyer dashboard stats error:', err);
                return res.status(500).json({ error: "Database error." });
              }
              
              console.log('📊 Buyer Dashboard Stats for User:', decoded.id);
              console.log('  Total Orders:', results[0].total_orders);
              console.log('  Total Spent:', results[0].total_spent);
              console.log('  Products Available:', results[0].total_products);
              console.log('  Pending Orders:', results[0].pending_orders);
              console.log('  Completed Orders:', results[0].completed_orders);
              
              res.json({
                total_orders: results[0].total_orders || 0,
                total_revenue: parseFloat(results[0].total_spent) || 0.0,
                total_products: results[0].total_products || 0,
                pending_orders: results[0].pending_orders || 0,
                completed_orders: results[0].completed_orders || 0,
                user_type: 'buyer'
              });
            }
          );
        }
      }
    );
  });
});

// -------- GET NOTIFICATIONS --------
app.get("/api/notifications", (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: "No token provided." });

  const token = authHeader.split(" ")[1];
  jwt.verify(token, SECRET_KEY, (err) => {
    if (err) return res.status(401).json({ error: "Invalid token." });

    db.query(
      "SELECT title, message, type, created_at FROM notifications ORDER BY created_at DESC LIMIT 10",
      (err, results) => {
        if (err) return res.status(500).json({ error: "Database error." });
        const messages = results.map(r => `${r.title}: ${r.message}`);
        res.json({ notifications: messages.length > 0 ? messages : ["No new notifications"] });
      }
    );
  });
});

// -------- REQUEST SELLER --------
app.post("/api/request-seller", (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: "No token provided." });
  
  const token = authHeader.split(" ")[1];
  jwt.verify(token, SECRET_KEY, (err, decoded) => {
    if (err) return res.status(401).json({ error: "Invalid token." });

    db.query(
      "SELECT role, is_approved FROM users WHERE id = ?",
      [decoded.id],
      (err, results) => {
        if (err) return res.status(500).json({ error: "Database error." });
        
        const user = results[0];
        
        if (user.role === 'seller' && user.is_approved === 1) {
          return res.json({ message: "You are already an approved seller." });
        }
        
        if (user.role === 'seller' && user.is_approved === 0) {
          return res.json({ message: "Your seller request is pending approval." });
        }

        db.query(
          "UPDATE users SET role = 'seller', is_approved = 0 WHERE id = ?",
          [decoded.id],
          (err2) => {
            if (err2) return res.status(500).json({ error: "Database error." });
            
            // Add notification
            db.query(
              "INSERT INTO notifications (title, message, type) VALUES (?, ?, ?)",
              ["Seller Request", `User ${decoded.id} requested seller access`, "warning"],
              () => {}
            );
            
            return res.json({ 
              message: "Seller request submitted successfully! Please wait for admin approval." 
            });
          }
        );
      }
    );
  });
});

// -------- GET USER INFO --------
app.get("/api/me", (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: "No token provided." });

  const token = authHeader.split(" ")[1];
  jwt.verify(token, SECRET_KEY, (err, decoded) => {
    if (err) return res.status(401).json({ error: "Invalid token." });

    db.query(
      "SELECT id, username, email, role, is_approved, is_admin FROM users WHERE id = ?",
      [decoded.id],
      (err, results) => {
        if (err) return res.status(500).json({ error: "Database error." });
        if (results.length === 0) return res.status(404).json({ error: "User not found." });
        res.json({ user: results[0] });
      }
    );
  });
});

// -------- GET SELLER ANALYTICS --------
app.get("/api/seller/analytics", authenticateToken, (req, res) => {
  const sellerId = req.userId;

  const analyticsQuery = `
    SELECT 
      -- Last 24 hours
      (SELECT COUNT(*) FROM orders 
       WHERE seller_id = ? 
       AND status IN ('Accepted', 'Confirmed', 'Shipped', 'Completed')
       AND created_at >= DATE_SUB(NOW(), INTERVAL 1 DAY)) AS orders_1day,
      (SELECT IFNULL(SUM(price * quantity), 0) FROM orders 
       WHERE seller_id = ? 
       AND status IN ('Accepted', 'Confirmed', 'Shipped', 'Completed')
       AND created_at >= DATE_SUB(NOW(), INTERVAL 1 DAY)) AS revenue_1day,
      (SELECT IFNULL(SUM(quantity), 0) FROM orders 
       WHERE seller_id = ? 
       AND status IN ('Accepted', 'Confirmed', 'Shipped', 'Completed')
       AND created_at >= DATE_SUB(NOW(), INTERVAL 1 DAY)) AS sales_1day,
      
      -- Last 7 days
      (SELECT COUNT(*) FROM orders 
       WHERE seller_id = ? 
       AND status IN ('Accepted', 'Confirmed', 'Shipped', 'Completed')
       AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)) AS orders_7days,
      (SELECT IFNULL(SUM(price * quantity), 0) FROM orders 
       WHERE seller_id = ? 
       AND status IN ('Accepted', 'Confirmed', 'Shipped', 'Completed')
       AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)) AS revenue_7days,
      (SELECT IFNULL(SUM(quantity), 0) FROM orders 
       WHERE seller_id = ? 
       AND status IN ('Accepted', 'Confirmed', 'Shipped', 'Completed')
       AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)) AS sales_7days,
      
      -- Last 30 days
      (SELECT COUNT(*) FROM orders 
       WHERE seller_id = ? 
       AND status IN ('Accepted', 'Confirmed', 'Shipped', 'Completed')
       AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)) AS orders_30days,
      (SELECT IFNULL(SUM(price * quantity), 0) FROM orders 
       WHERE seller_id = ? 
       AND status IN ('Accepted', 'Confirmed', 'Shipped', 'Completed')
       AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)) AS revenue_30days,
      (SELECT IFNULL(SUM(quantity), 0) FROM orders 
       WHERE seller_id = ? 
       AND status IN ('Accepted', 'Confirmed', 'Shipped', 'Completed')
       AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)) AS sales_30days,
      
      -- All time
      (SELECT COUNT(*) FROM orders 
       WHERE seller_id = ? 
       AND status IN ('Accepted', 'Confirmed', 'Shipped', 'Completed')) AS orders_alltime,
      (SELECT IFNULL(SUM(price * quantity), 0) FROM orders 
       WHERE seller_id = ? 
       AND status IN ('Accepted', 'Confirmed', 'Shipped', 'Completed')) AS revenue_alltime,
      (SELECT IFNULL(SUM(quantity), 0) FROM orders 
       WHERE seller_id = ? 
       AND status IN ('Accepted', 'Confirmed', 'Shipped', 'Completed')) AS sales_alltime
  `;

  db.query(
    analyticsQuery,
    [
      sellerId, sellerId, sellerId, // 1 day
      sellerId, sellerId, sellerId, // 7 days
      sellerId, sellerId, sellerId, // 30 days
      sellerId, sellerId, sellerId  // all time
    ],
    (err, results) => {
      if (err) {
        console.error('Analytics query error:', err);
        return res.status(500).json({ error: "Database error." });
      }

      const data = results[0];

      res.json({
        '1day': {
          total_orders: data.orders_1day || 0,
          total_revenue: parseFloat(data.revenue_1day) || 0.0,
          total_sales: data.sales_1day || 0
        },
        '7days': {
          total_orders: data.orders_7days || 0,
          total_revenue: parseFloat(data.revenue_7days) || 0.0,
          total_sales: data.sales_7days || 0
        },
        '30days': {
          total_orders: data.orders_30days || 0,
          total_revenue: parseFloat(data.revenue_30days) || 0.0,
          total_sales: data.sales_30days || 0
        },
        'alltime': {
          total_orders: data.orders_alltime || 0,
          total_revenue: parseFloat(data.revenue_alltime) || 0.0,
          total_sales: data.sales_alltime || 0
        }
      });
    }
  );
});

// -------- SUBMIT RATING AFTER ORDER COMPLETION --------
// -------- BUYER CONFIRMS RECEIPT & COMPLETES ORDER --------
app.post("/api/orders/:orderId/complete", authenticateToken, (req, res) => {
  const buyerId = req.userId;
  const orderId = req.params.orderId;

  db.query(
    "SELECT * FROM orders WHERE id = ? AND user_id = ?",
    [orderId, buyerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];

      if (!order.seller_shipped) {
        return res.status(400).json({ error: "Seller hasn't marked order as shipped yet." });
      }

      // ✅ Update BOTH order status AND payment status
      db.query(
        "UPDATE orders SET buyer_confirmed_receipt = 1, status = 'Completed', payment_status = 'completed', completion_date = NOW() WHERE id = ?",
        [orderId],
        (err) => {
          if (err) return res.status(500).json({ error: "Failed to complete order." });

           db.query(
            `INSERT INTO blockchain_transactions 
             (type, product, buyer, seller, price, quantity, status, order_id, created_at) 
             VALUES ('order', ?, 
                     (SELECT username FROM users WHERE id = ?), 
                     (SELECT username FROM users WHERE id = ?), 
                     ?, ?, 'Completed', ?, NOW())`,
            [
              order.product_name,
              order.user_id,
              order.seller_id,
              order.price,
              order.quantity,
              orderId
            ],
            (err) => {
              if (err) {
                console.error('❌ Failed to create blockchain transaction:', err);
              } else {
                console.log('✅ Blockchain transaction created for order:', orderId);
              }
            }
          );


          // Automatically release escrow
          db.query(
            `UPDATE payments 
             SET escrow_status = 'released', 
                 released_at = NOW(),
                 updated_at = NOW()
             WHERE order_id = ? AND escrow_status = 'held'`,
            [orderId],
            () => {}
          );

          // Notify seller
          createNotification(
            order.seller_id,
            '✅ Order Completed & Payment Released',
            `Order for ${order.product_name} completed. Payment of ₱${order.price} released from escrow.`,
            'order_completed',
            orderId,
            'order'
          );

          // Send message
          if (order.conversation_id) {
            const completeMessage = `✅ Order Completed\n\nBuyer has confirmed receipt of ${order.product_name}.\n\nPayment has been released to seller.\n\nThank you for your transaction!`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, buyerId, completeMessage],
              () => {}
            );
          }

          res.json({ 
            message: "Order completed successfully! Payment released to seller.",
            escrow_released: true 
          });
        }
      );
    }
  );
});

// -------- GET SELLER RATING STATISTICS --------
app.get("/api/seller/rating-stats", authenticateToken, (req, res) => {
  const sellerId = req.userId;

  const statsQuery = `
    SELECT 
      COUNT(*) as total_ratings,
      AVG(rating) as average_rating,
      SUM(CASE WHEN rating = 5 THEN 1 ELSE 0 END) as five_star,
      SUM(CASE WHEN rating = 4 THEN 1 ELSE 0 END) as four_star,
      SUM(CASE WHEN rating = 3 THEN 1 ELSE 0 END) as three_star,
      SUM(CASE WHEN rating = 2 THEN 1 ELSE 0 END) as two_star,
      SUM(CASE WHEN rating = 1 THEN 1 ELSE 0 END) as one_star
    FROM ratings
    WHERE seller_id = ?
  `;

  db.query(statsQuery, [sellerId], (err, results) => {
    if (err) return res.status(500).json({ error: "Database error." });

    const stats = results[0];
    res.json({
      total_ratings: stats.total_ratings || 0,
      average_rating: stats.average_rating ? parseFloat(stats.average_rating).toFixed(1) : '0.0',
      breakdown: {
        five_star: stats.five_star || 0,
        four_star: stats.four_star || 0,
        three_star: stats.three_star || 0,
        two_star: stats.two_star || 0,
        one_star: stats.one_star || 0,
      }
    });
  });
});

// -------- GET SELLER PROFILE STATISTICS --------
app.get("/api/seller/profile-stats", authenticateToken, (req, res) => {
  const sellerId = req.userId;

  const statsQuery = `
    SELECT 
      (SELECT COUNT(*) FROM products WHERE seller_id = ?) as total_products,
      (SELECT IFNULL(SUM(price * quantity), 0) FROM orders 
       WHERE seller_id = ? AND status = 'Completed') as total_revenue,
      (SELECT COUNT(*) FROM orders 
       WHERE seller_id = ? AND status = 'Completed') as total_sales,
      (SELECT AVG(rating) FROM ratings WHERE seller_id = ?) as average_rating,
      (SELECT COUNT(*) FROM ratings WHERE seller_id = ?) as total_ratings
  `;

  db.query(
    statsQuery,
    [sellerId, sellerId, sellerId, sellerId, sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });

      const stats = results[0];
      res.json({
        total_products: stats.total_products || 0,
        total_revenue: parseFloat(stats.total_revenue) || 0.0,
        total_sales: stats.total_sales || 0,
        average_rating: stats.average_rating ? parseFloat(stats.average_rating).toFixed(1) : '0.0',
        total_ratings: stats.total_ratings || 0,
      });
    }
  );
});

app.post("/api/messages/upload-media", authenticateToken, upload.single('media'), (req, res) => {
  const userId = req.userId;
  const { conversation_id } = req.body;

  console.log('📸 Media upload request:', {
    userId,
    conversation_id,
    file: req.file ? req.file.filename : 'none'
  });

  if (!conversation_id) {
    return res.status(400).json({ error: "Conversation ID is required." });
  }

  if (!req.file) {
    return res.status(400).json({ error: "No file uploaded." });
  }

  // Verify user has access to conversation
  db.query(
    "SELECT * FROM conversations WHERE id = ? AND (user1_id = ? OR user2_id = ?)",
    [conversation_id, userId, userId],
    (err, convResults) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (convResults.length === 0) {
        return res.status(403).json({ error: "Unauthorized access to conversation." });
      }

      const mediaUrl = `/uploads/${req.file.filename}`;
      const fileType = req.file.mimetype.startsWith('image/') ? 'image' : 'file';

      // Insert message with media
      db.query(
        `INSERT INTO messages (conversation_id, sender_id, message, message_type, media_url) 
         VALUES (?, ?, ?, ?, ?)`,
        [conversation_id, userId, fileType === 'image' ? '📷 Image' : '📎 File', fileType, mediaUrl],
        (err, result) => {
          if (err) {
            console.error('Failed to save media message:', err);
            return res.status(500).json({ error: "Failed to save message." });
          }

          console.log('✅ Media message saved:', result.insertId);

          res.status(201).json({
            message: "Media uploaded successfully.",
            message_id: result.insertId,
            media_url: mediaUrl,
            message_type: fileType
          });
        }
      );
    }
  );
});

// -------- GET MESSAGES (Updated to include media) --------
app.get("/api/messages/:conversationId", authenticateToken, (req, res) => {
  const conversationId = req.params.conversationId;
  const userId = req.userId;

  // Verify access
  db.query(
    "SELECT * FROM conversations WHERE id = ? AND (user1_id = ? OR user2_id = ?)",
    [conversationId, userId, userId],
    (err, convResults) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (convResults.length === 0) {
        return res.status(403).json({ error: "Unauthorized access to conversation." });
      }

      // Mark messages as read
      db.query(
        "UPDATE messages SET is_read = 1 WHERE conversation_id = ? AND sender_id != ?",
        [conversationId, userId],
        () => {}
      );

      // Get messages with media info
      const query = `
        SELECT 
          m.*,
          u.username as sender_name,
          u.role as sender_role
        FROM messages m
        LEFT JOIN users u ON m.sender_id = u.id
        WHERE m.conversation_id = ?
        ORDER BY m.created_at ASC
      `;

      db.query(query, [conversationId], (err, results) => {
        if (err) return res.status(500).json({ error: "Database error." });
        res.json({ messages: results });
      });
    }
  );
});

// -------- DELETE MEDIA MESSAGE --------
app.delete("/api/messages/:messageId", authenticateToken, (req, res) => {
  const userId = req.userId;
  const messageId = req.params.messageId;

  // Verify user owns this message
  db.query(
    "SELECT * FROM messages WHERE id = ? AND sender_id = ?",
    [messageId, userId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Message not found or unauthorized." });
      }

      const message = results[0];

      // Delete file if exists
      if (message.media_url) {
        const filePath = path.join(__dirname, message.media_url);
        if (fs.existsSync(filePath)) {
          fs.unlinkSync(filePath);
        }
      }

      // Delete message
      db.query(
        "DELETE FROM messages WHERE id = ?",
        [messageId],
        (err) => {
          if (err) return res.status(500).json({ error: "Failed to delete message." });
          res.json({ message: "Message deleted successfully." });
        }
      );
    }
  );
});

// -------- GET RECENT RATINGS FOR SELLER --------
app.get("/api/seller/recent-ratings", authenticateToken, (req, res) => {
  const sellerId = req.userId;
  const limit = req.query.limit || 10;

  const query = `
    SELECT r.*, u.username as buyer_name, o.product_name
    FROM ratings r
    LEFT JOIN users u ON r.buyer_id = u.id
    LEFT JOIN orders o ON r.order_id = o.id
    WHERE r.seller_id = ?
    ORDER BY r.created_at DESC
    LIMIT ?
  `;

  db.query(query, [sellerId, parseInt(limit)], (err, results) => {
    if (err) return res.status(500).json({ error: "Database error." });
    res.json({ ratings: results });
  });
});
// Add these payment routes to your server.js

// ============================================
// PAYMENT INTEGRATION WITH ESCROW SYSTEM
// ============================================

// PayMongo API Configuration (Get from https://dashboard.paymongo.com)
const PAYMONGO_SECRET_KEY = 'sk_test_your_secret_key_here'; // REPLACE WITH YOUR KEY
const PAYMONGO_PUBLIC_KEY = 'pk_test_your_public_key_here'; // REPLACE WITH YOUR KEY

// -------- CREATE PAYMENT INTENT --------
app.post("/api/payments/create-intent", authenticateToken, async (req, res) => {
  const userId = req.userId;
  const { order_id, amount, payment_method } = req.body;

  if (!order_id || !amount || !payment_method) {
    return res.status(400).json({ error: "Missing required fields." });
  }

  try {
    // Verify order belongs to user
    db.query(
      "SELECT * FROM orders WHERE id = ? AND user_id = ?",
      [order_id, userId],
      async (err, orderResults) => {
        if (err) return res.status(500).json({ error: "Database error." });
        if (orderResults.length === 0) {
          return res.status(404).json({ error: "Order not found." });
        }

        const order = orderResults[0];

        // Check if payment already exists
        db.query(
          "SELECT * FROM payments WHERE order_id = ? AND status IN ('pending', 'completed')",
          [order_id],
          (err, existingPayments) => {
            if (err) return res.status(500).json({ error: "Database error." });
            if (existingPayments.length > 0) {
              return res.status(400).json({ error: "Payment already exists for this order." });
            }

            // Create payment record in escrow
            db.query(
              `INSERT INTO payments 
               (order_id, user_id, seller_id, amount, payment_method, status, escrow_status) 
               VALUES (?, ?, ?, ?, ?, 'pending', 'held')`,
              [order_id, userId, order.seller_id, amount, payment_method],
              (err, result) => {
                if (err) return res.status(500).json({ error: "Failed to create payment." });

                const paymentId = result.insertId;

                res.json({
                  payment_id: paymentId,
                  order_id: order_id,
                  amount: amount,
                  status: 'pending',
                  escrow_status: 'held',
                  message: 'Payment intent created successfully.'
                });
              }
            );
          }
        );
      }
    );
  } catch (e) {
    res.status(500).json({ error: "Server error." });
  }
});

// -------- PROCESS GCASH PAYMENT (PayMongo) --------
app.post("/api/payments/gcash", authenticateToken, async (req, res) => {
  const userId = req.userId;
  const { order_id, amount, phone_number } = req.body;

  try {
    // Create PayMongo GCash source
    const response = await fetch('https://api.paymongo.com/v1/sources', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Basic ${Buffer.from(PAYMONGO_SECRET_KEY).toString('base64')}`
      },
      body: JSON.stringify({
        data: {
          attributes: {
            type: 'gcash',
            amount: Math.round(amount * 100), // Convert to centavos
            currency: 'PHP',
            redirect: {
              success: 'https://yourdomain.com/payment/success',
              failed: 'https://yourdomain.com/payment/failed'
            },
            billing: {
              phone: phone_number
            }
          }
        }
      })
    });

    const paymongoData = await response.json();

    if (!response.ok) {
      throw new Error(paymongoData.errors?.[0]?.detail || 'PayMongo error');
    }

    const sourceId = paymongoData.data.id;
    const checkoutUrl = paymongoData.data.attributes.redirect.checkout_url;

    // Update payment with PayMongo source
    db.query(
      `UPDATE payments 
       SET paymongo_source_id = ?, checkout_url = ?, updated_at = NOW() 
       WHERE order_id = ? AND user_id = ?`,
      [sourceId, checkoutUrl, order_id, userId],
      (err) => {
        if (err) return res.status(500).json({ error: "Failed to update payment." });

        // Notify seller that payment is processing
        createNotification(
          userId,
          'Payment Processing',
          `GCash payment for order #${order_id} is being processed.`,
          'payment',
          order_id,
          'order'
        );

        res.json({
          success: true,
          checkout_url: checkoutUrl,
          source_id: sourceId,
          message: 'GCash payment initiated. Please complete payment in browser.'
        });
      }
    );

  } catch (e) {
    console.error('GCash payment error:', e);
    res.status(500).json({ error: e.message || 'Failed to process GCash payment.' });
  }
});

// -------- PROCESS CARD PAYMENT (PayMongo) --------
app.post("/api/payments/card", authenticateToken, async (req, res) => {
  const userId = req.userId;
  const { order_id, amount, card_number, exp_month, exp_year, cvc, cardholder_name } = req.body;

  try {
    // Step 1: Create payment method
    const pmResponse = await fetch('https://api.paymongo.com/v1/payment_methods', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Basic ${Buffer.from(PAYMONGO_SECRET_KEY).toString('base64')}`
      },
      body: JSON.stringify({
        data: {
          attributes: {
            type: 'card',
            details: {
              card_number: card_number,
              exp_month: parseInt(exp_month),
              exp_year: parseInt(exp_year),
              cvc: cvc
            },
            billing: {
              name: cardholder_name
            }
          }
        }
      })
    });

    const pmData = await pmResponse.json();
    if (!pmResponse.ok) {
      throw new Error(pmData.errors?.[0]?.detail || 'Invalid card details');
    }

    const paymentMethodId = pmData.data.id;

    // Step 2: Create payment intent
    const piResponse = await fetch('https://api.paymongo.com/v1/payment_intents', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Basic ${Buffer.from(PAYMONGO_SECRET_KEY).toString('base64')}`
      },
      body: JSON.stringify({
        data: {
          attributes: {
            amount: Math.round(amount * 100),
            payment_method_allowed: ['card'],
            payment_method_options: {
              card: { request_three_d_secure: 'any' }
            },
            currency: 'PHP',
            description: `Payment for order #${order_id}`
          }
        }
      })
    });

    const piData = await piResponse.json();
    if (!piResponse.ok) {
      throw new Error(piData.errors?.[0]?.detail || 'Payment intent failed');
    }

    const paymentIntentId = piData.data.id;

    // Step 3: Attach payment method to intent
    const attachResponse = await fetch(
      `https://api.paymongo.com/v1/payment_intents/${paymentIntentId}/attach`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Basic ${Buffer.from(PAYMONGO_SECRET_KEY).toString('base64')}`
        },
        body: JSON.stringify({
          data: {
            attributes: {
              payment_method: paymentMethodId
            }
          }
        })
      }
    );

    const attachData = await attachResponse.json();
    if (!attachResponse.ok) {
      throw new Error(attachData.errors?.[0]?.detail || 'Payment attachment failed');
    }

    // Update payment record
    db.query(
      `UPDATE payments 
       SET paymongo_payment_intent_id = ?, 
           paymongo_payment_method_id = ?,
           status = 'completed',
           escrow_status = 'held',
           completed_at = NOW(),
           updated_at = NOW()
       WHERE order_id = ? AND user_id = ?`,
      [paymentIntentId, paymentMethodId, order_id, userId],
      (err) => {
        if (err) return res.status(500).json({ error: "Failed to update payment." });

        // Update order status
        db.query(
          "UPDATE orders SET payment_status = 'paid' WHERE id = ?",
          [order_id],
          () => {}
        );

        // Notify both parties
        db.query(
          "SELECT seller_id FROM orders WHERE id = ?",
          [order_id],
          (err, orderResults) => {
            if (!err && orderResults.length > 0) {
              const sellerId = orderResults[0].seller_id;
              
              createNotification(
                userId,
                'Payment Successful',
                `Your payment of ₱${amount.toFixed(2)} is held securely in escrow.`,
                'payment',
                order_id,
                'order'
              );

              createNotification(
                sellerId,
                'Payment Received',
                `Buyer has paid ₱${amount.toFixed(2)}. Funds will be released after delivery confirmation.`,
                'payment',
                order_id,
                'order'
              );
            }
          }
        );

        res.json({
          success: true,
          payment_intent_id: paymentIntentId,
          status: 'completed',
          escrow_status: 'held',
          message: 'Card payment successful. Funds held in escrow.'
        });
      }
    );

  } catch (e) {
    console.error('Card payment error:', e);
    res.status(500).json({ error: e.message || 'Failed to process card payment.' });
  }
});

// -------- VERIFY PAYMENT STATUS --------
app.get("/api/payments/verify/:paymentIntentId", authenticateToken, async (req, res) => {
  const { paymentIntentId } = req.params;

  try {
    const response = await fetch(
      `https://api.paymongo.com/v1/payment_intents/${paymentIntentId}`,
      {
        headers: {
          'Authorization': `Basic ${Buffer.from(PAYMONGO_SECRET_KEY).toString('base64')}`
        }
      }
    );

    const data = await response.json();

    if (!response.ok) {
      throw new Error('Failed to verify payment');
    }

    res.json({
      status: data.data.attributes.status,
      amount: data.data.attributes.amount / 100,
      currency: data.data.attributes.currency
    });

  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// -------- GET PAYMENT HISTORY --------
app.get("/api/payments/history", authenticateToken, (req, res) => {
  const userId = req.userId;

  db.query(
    `SELECT 
      p.*,
      o.product_name,
      o.quantity,
      o.user_id as order_buyer_id,
      o.seller_id as order_seller_id,
      CASE 
        WHEN p.user_id = ? THEN 'buyer'
        WHEN p.seller_id = ? THEN 'seller'
        ELSE 'unknown'
      END as user_role
     FROM payments p
     LEFT JOIN orders o ON p.order_id = o.id
     WHERE p.user_id = ? OR p.seller_id = ?
     ORDER BY p.created_at DESC
     LIMIT 50`,
    [userId, userId, userId, userId],
    (err, results) => {
      if (err) {
        console.error('Payment history error:', err);
        return res.status(500).json({ error: "Database error." });
      }
      
      // ✅ Convert amount and verify user role
      const payments = results.map(payment => {
        const isBuyer = payment.user_id === userId;
        const isSeller = payment.seller_id === userId;
        
        console.log('Payment:', {
          id: payment.id,
          user_id: payment.user_id,
          seller_id: payment.seller_id,
          current_user: userId,
          calculated_role: isBuyer ? 'buyer' : (isSeller ? 'seller' : 'unknown')
        });
        
        return {
          ...payment,
          amount: parseFloat(payment.amount) || 0.0,
          user_role: isBuyer ? 'buyer' : (isSeller ? 'seller' : 'unknown')
        };
      });
      
      res.json({ payments });
    }
  );
});

// -------- GET ESCROW STATUS --------
app.get("/api/payments/escrow/:orderId", authenticateToken, (req, res) => {
  const userId = req.userId;
  const orderId = req.params.orderId;

  db.query(
    `SELECT p.*, o.status as order_status
     FROM payments p
     LEFT JOIN orders o ON p.order_id = o.id
     WHERE p.order_id = ? AND (p.user_id = ? OR p.seller_id = ?)`,
    [orderId, userId, userId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Payment not found." });
      }

      const payment = results[0];
      res.json({
        escrow_status: payment.escrow_status,
        amount: payment.amount,
        order_status: payment.order_status,
        can_release: payment.order_status === 'Completed' && payment.escrow_status === 'held',
        can_refund: payment.escrow_status === 'held' && ['Cancelled', 'Disputed'].includes(payment.order_status)
      });
    }
  );
});

// -------- RELEASE ESCROW (When buyer confirms delivery) --------
app.post("/api/payments/release-escrow", authenticateToken, (req, res) => {
  const userId = req.userId;
  const { order_id } = req.body;

  // Verify buyer owns this order
  db.query(
    "SELECT * FROM orders WHERE id = ? AND user_id = ?",
    [order_id, userId],
    (err, orderResults) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (orderResults.length === 0) {
        return res.status(404).json({ error: "Order not found." });
      }

      const order = orderResults[0];

      if (order.status !== 'Completed') {
        return res.status(400).json({ error: "Order must be completed first." });
      }

      // Update payment escrow status
      db.query(
        `UPDATE payments 
         SET escrow_status = 'released', 
             released_at = NOW(),
             updated_at = NOW()
         WHERE order_id = ? AND escrow_status = 'held'`,
        [order_id],
        (err, result) => {
          if (err) return res.status(500).json({ error: "Failed to release escrow." });
          if (result.affectedRows === 0) {
            return res.status(400).json({ error: "Escrow already released or not found." });
          }

          // Notify seller - they can now receive the money
          createNotification(
            order.seller_id,
            '💰 Payment Released',
            `Payment for order #${order_id} has been released from escrow. Funds will be transferred to your account.`,
            'payment',
            order_id,
            'order'
          );

          res.json({ 
            message: 'Escrow released successfully. Seller will receive payment.',
            status: 'released'
          });
        }
      );
    }
  );
});

// -------- REQUEST REFUND --------
app.post("/api/payments/refund", authenticateToken, async (req, res) => {
  const userId = req.userId;
  const { order_id, reason } = req.body;

  try {
    // Verify user is buyer
    db.query(
      "SELECT * FROM orders WHERE id = ? AND user_id = ?",
      [order_id, userId],
      (err, orderResults) => {
        if (err) return res.status(500).json({ error: "Database error." });
        if (orderResults.length === 0) {
          return res.status(404).json({ error: "Order not found." });
        }

        const order = orderResults[0];

        // Check if refund is allowed
        if (!['Cancelled', 'Disputed'].includes(order.status)) {
          return res.status(400).json({ error: "Refund not allowed for this order status." });
        }

        // Get payment details
        db.query(
          "SELECT * FROM payments WHERE order_id = ? AND escrow_status = 'held'",
          [order_id],
          async (err, paymentResults) => {
            if (err) return res.status(500).json({ error: "Database error." });
            if (paymentResults.length === 0) {
              return res.status(404).json({ error: "No payment found in escrow." });
            }

            const payment = paymentResults[0];

            // Process refund through PayMongo if applicable
            let refundId = null;
            if (payment.paymongo_payment_intent_id) {
              try {
                const refundResponse = await fetch('https://api.paymongo.com/v1/refunds', {
                  method: 'POST',
                  headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Basic ${Buffer.from(PAYMONGO_SECRET_KEY).toString('base64')}`
                  },
                  body: JSON.stringify({
                    data: {
                      attributes: {
                        amount: Math.round(payment.amount * 100),
                        payment_intent: payment.paymongo_payment_intent_id,
                        reason: 'requested_by_customer',
                        notes: reason
                      }
                    }
                  })
                });

                const refundData = await refundResponse.json();
                if (refundResponse.ok) {
                  refundId = refundData.data.id;
                }
              } catch (e) {
                console.error('Refund error:', e);
              }
            }

            // Update payment status
            db.query(
              `UPDATE payments 
               SET escrow_status = 'refunded',
                   refund_reason = ?,
                   paymongo_refund_id = ?,
                   refunded_at = NOW(),
                   updated_at = NOW()
               WHERE id = ?`,
              [reason, refundId, payment.id],
              (err) => {
                if (err) return res.status(500).json({ error: "Failed to process refund." });

                // Notify both parties
                createNotification(
                  userId,
                  'Refund Processed',
                  `Your refund of ₱${payment.amount.toFixed(2)} has been initiated.`,
                  'payment',
                  order_id,
                  'order'
                );

                createNotification(
                  order.seller_id,
                  'Order Refunded',
                  `Order #${order_id} has been refunded to the buyer.`,
                  'payment',
                  order_id,
                  'order'
                );

                res.json({
                  message: 'Refund processed successfully.',
                  refund_id: refundId,
                  amount: payment.amount,
                  status: 'refunded'
                });
              }
            );
          }
        );
      }
    );
  } catch (e) {
    res.status(500).json({ error: "Server error." });
  }
});

// -------- DOWNLOAD RECEIPT --------
app.get("/api/payments/receipt/:paymentId", authenticateToken, (req, res) => {
  const userId = req.userId;
  const paymentId = req.params.paymentId;

  db.query(
    `SELECT p.*, o.product_name, o.quantity,
            u1.username as buyer_name, u1.email as buyer_email,
            u2.username as seller_name, u2.email as seller_email
     FROM payments p
     LEFT JOIN orders o ON p.order_id = o.id
     LEFT JOIN users u1 ON p.user_id = u1.id
     LEFT JOIN users u2 ON p.seller_id = u2.id
     WHERE p.id = ? AND (p.user_id = ? OR p.seller_id = ?)`,
    [paymentId, userId, userId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Receipt not found." });
      }

      const receipt = results[0];
      res.json({
        receipt_id: receipt.id,
        date: receipt.completed_at || receipt.created_at,
        order_id: receipt.order_id,
        product_name: receipt.product_name,
        quantity: receipt.quantity,
        amount: receipt.amount,
        payment_method: receipt.payment_method,
        buyer: {
          name: receipt.buyer_name,
          email: receipt.buyer_email
        },
        seller: {
          name: receipt.seller_name,
          email: receipt.seller_email
        },
        status: receipt.status,
        escrow_status: receipt.escrow_status
      });
    }
  );
});

// -------- AUTOMATIC ESCROW RELEASE (When buyer confirms delivery) --------
// Update the buyer complete order endpoint to automatically release escrow
app.post("/api/orders/:orderId/complete", authenticateToken, (req, res) => {
  const buyerId = req.userId;
  const orderId = req.params.orderId;

  db.query(
    "SELECT * FROM orders WHERE id = ? AND user_id = ?",
    [orderId, buyerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];

      if (!order.seller_shipped) {
        return res.status(400).json({ error: "Seller hasn't marked order as shipped yet." });
      }

      // ✅ Update BOTH order status AND payment status
      db.query(
        "UPDATE orders SET buyer_confirmed_receipt = 1, status = 'Completed', payment_status = 'completed', completion_date = NOW() WHERE id = ?",
        [orderId],
        (err) => {
          if (err) return res.status(500).json({ error: "Failed to complete order." });

          // Automatically release escrow
          db.query(
            `UPDATE payments 
             SET escrow_status = 'released', 
                 released_at = NOW(),
                 updated_at = NOW()
             WHERE order_id = ? AND escrow_status = 'held'`,
            [orderId],
            () => {}
          );

          // Notify seller
          createNotification(
            order.seller_id,
            '✅ Order Completed & Payment Released',
            `Order for ${order.product_name} completed. Payment of ₱${order.price} released from escrow.`,
            'order_completed',
            orderId,
            'order'
          );

          // Send message
          if (order.conversation_id) {
            const completeMessage = `✅ Order Completed\n\nBuyer has confirmed receipt of ${order.product_name}.\n\nPayment has been released to seller.\n\nThank you for your transaction!`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, buyerId, completeMessage],
              () => {}
            );
          }

          res.json({ 
            message: "Order completed successfully! Payment released to seller.",
            escrow_released: true 
          });
        }
      );
    }
  );
});
// -------- AUTOMATIC REFUND (When order is cancelled) --------
app.post("/api/orders/:orderId/seller-cancel-accepted", authenticateToken, async (req, res) => {
  const sellerId = req.userId;
  const orderId = req.params.orderId;
  const { reason } = req.body;

  db.query(
    "SELECT * FROM orders WHERE id = ? AND seller_id = ?",
    [orderId, sellerId],
    async (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found." });
      }

      const order = results[0];

      // Cancel order
      db.query(
        "UPDATE orders SET status = 'Cancelled' WHERE id = ?",
        [orderId],
        () => {}
      );

      // Automatically process refund
      db.query(
        "SELECT * FROM payments WHERE order_id = ? AND escrow_status = 'held'",
        [orderId],
        async (err, paymentResults) => {
          if (err || paymentResults.length === 0) {
            return res.json({ message: "Order cancelled (no payment to refund)." });
          }

          const payment = paymentResults[0];

          // Update payment to refunded
          db.query(
            `UPDATE payments 
             SET escrow_status = 'refunded',
                 refund_reason = ?,
                 refunded_at = NOW()
             WHERE id = ?`,
            [reason || 'Seller cancelled order', payment.id],
            () => {}
          );

          // Notify buyer
          createNotification(
            order.user_id,
            'Order Cancelled - Refund Processed',
            `Your order has been cancelled. Refund of ₱${payment.amount.toFixed(2)} will be processed.`,
            'payment',
            orderId,
            'order'
          );

          res.json({ 
            message: 'Order cancelled and refund processed.',
            refund_amount: payment.amount
          });
        }
      );
    }
  );
});

// -------- PROCESS PAYMENT (ENHANCED with detailed error logging) --------
app.post("/api/payments/process", authenticateToken, async (req, res) => {
  const userId = req.userId;
  const { 
    order_id, 
    amount, 
    payment_method, 
    phone_number,
    card_last4,
    cardholder_name,
    bank_name,
    account_number,
    account_name,
    reference_number 
  } = req.body;

  console.log('💳 Processing payment for order:', order_id);

  if (!order_id || !amount || !payment_method) {
    return res.status(400).json({ 
      error: "Missing required fields: order_id, amount, and payment_method are required." 
    });
  }

  const validMethods = ['gcash', 'card', 'bank', 'cod'];
  if (!validMethods.includes(payment_method.toLowerCase())) {
    return res.status(400).json({ 
      error: "Invalid payment method. Must be: gcash, card, bank, or cod." 
    });
  }

  try {
    // 1️⃣ Verify order exists and belongs to user
    db.query(
      "SELECT * FROM orders WHERE id = ? AND user_id = ?",
      [order_id, userId],
      (err, orderResults) => {
        if (err) {
          console.error('❌ Database error:', err);
          return res.status(500).json({ error: "Database error." });
        }
        
        if (orderResults.length === 0) {
          return res.status(404).json({ 
            error: "Order not found or does not belong to you." 
          });
        }

        const order = orderResults[0];

        // ✅ CHECK IF ORDER IS ACCEPTED
        if (order.status !== 'Accepted') {
          return res.status(400).json({ 
            error: "Order must be accepted by seller before payment." 
          });
        }

        // Check if seller_id exists
        if (!order.seller_id) {
          return res.status(400).json({ 
            error: "This order has no seller assigned." 
          });
        }

        // 2️⃣ Check if payment already exists
        db.query(
          "SELECT * FROM payments WHERE order_id = ?",
          [order_id],
          (err, existingPayments) => {
            if (err) {
              return res.status(500).json({ error: "Database error checking payments." });
            }
            
            if (existingPayments.length > 0) {
              return res.status(400).json({ 
                error: "Payment already exists for this order." 
              });
            }

            // 3️⃣ Validate amount
            const orderTotal = parseFloat(order.price);
            const paymentAmount = parseFloat(amount);
            
            if (Math.abs(orderTotal - paymentAmount) > 0.01) {
              return res.status(400).json({ 
                error: `Payment amount (₱${paymentAmount}) does not match order total (₱${orderTotal}).` 
              });
            }

            // 4️⃣ Create payment record
            const paymentValues = [
              order_id,
              userId,
              order.seller_id,
              amount,
              payment_method,
              reference_number || `${payment_method.toUpperCase()}-${Date.now()}`,
              'completed',
              'held',
              phone_number || null,
              card_last4 || null,
              cardholder_name || null,
              bank_name || null,
              account_number || null,
              account_name || null
            ];

            const paymentInsertQuery = `
              INSERT INTO payments 
              (order_id, user_id, seller_id, amount, payment_method, reference_number, 
               status, escrow_status, phone_number, card_last4, cardholder_name, 
               bank_name, account_number, account_name, completed_at) 
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
            `;

           db.query(
  paymentInsertQuery,
  paymentValues,
  (err, result) => {
    if (err) {
      console.error('❌ Failed to create payment:', err);
      return res.status(500).json({ 
        error: "Failed to create payment record.",
        details: err.sqlMessage || err.message
      });
    }


                const paymentId = result.insertId;
    console.log('✅ Payment created:', paymentId);

                // 5️⃣ ✅ UPDATE ORDER STATUS TO CONFIRMED (NOW SELLER CAN SHIP)
                db.query(
      "UPDATE orders SET payment_status = 'paid', status = 'Confirmed' WHERE id = ?",
      [order_id],
      (err) => {
        if (err) {
          console.error('⚠️ Failed to update order status:', err);
          // Continue anyway, payment was successful
        } else {
          console.log('✅ Order updated to Confirmed - Seller can now ship');
        }
                  }
                );

                // 6️⃣ Notify buyer
                createNotification(
                  userId,
                  '✅ Payment Successful',
                  `Your payment of ₱${amount.toFixed(2)} is held securely in escrow. Seller can now ship your order.`,
                  'payment_completed',
                  order_id,
                  'order'
                );

                // 7️⃣ Notify seller
                createNotification(
                  order.seller_id,
                  '💰 Payment Received',
                  `Buyer has paid ₱${amount.toFixed(2)} for ${order.product_name}. You can now ship the order. Funds will be released after delivery confirmation.`,
                  'payment_received',
                  order_id,
                  'order'
                );

                // 8️⃣ Send message
                if (order.conversation_id) {
                  const paymentMessage = `💳 Payment Completed\n\nAmount: ₱${amount.toFixed(2)}\nMethod: ${getPaymentMethodLabel(payment_method)}\nReference: ${reference_number || 'N/A'}\n\n🔒 Funds are held securely in escrow.\n\n📦 Seller can now ship your order.`;
                  
                  db.query(
                    "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
                    [order.conversation_id, userId, paymentMessage],
                    () => {}
                  );
                }

                res.status(201).json({
                  success: true,
                  message: 'Payment processed successfully. Order confirmed!',
                  payment_id: paymentId,
                  reference_number: reference_number || `${payment_method.toUpperCase()}-${Date.now()}`,
                  escrow_status: 'held',
                  amount: amount,
                  order_status: 'Confirmed'
                });
              }
            );
          }
        );
      }
    );
  } catch (e) {
    console.error('❌ Server error:', e);
    res.status(500).json({ 
      error: "Server error: " + e.message 
    });
  }
});

function getPaymentMethodLabel(method) {
  const labels = {
    'gcash': 'GCash',
    'card': 'Credit/Debit Card',
    'bank': 'Bank Transfer',
    'cod': 'Cash on Delivery'
  };
  return labels[method] || method;
}

// -------- PROCESS REFUND --------
app.post("/api/payments/refund/:orderId", authenticateToken, (req, res) => {
  const userId = req.userId;
  const orderId = req.params.orderId;
  const { reason } = req.body;

  db.query(
    "SELECT * FROM orders WHERE id = ? AND (user_id = ? OR seller_id = ?)",
    [orderId, userId, userId],
    (err, orderResults) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (orderResults.length === 0) {
        return res.status(404).json({ error: "Order not found." });
      }

      const order = orderResults[0];

      // Check if refund is allowed
      if (order.status !== 'Cancelled' && order.status !== 'Disputed') {
        return res.status(400).json({ error: "Refund only allowed for cancelled/disputed orders." });
      }

      // Process refund
      db.query(
        `UPDATE payments 
         SET escrow_status = 'refunded',
             refund_reason = ?,
             refunded_at = NOW()
         WHERE order_id = ? AND escrow_status = 'held'`,
        [reason || 'Order cancelled', orderId],
        (err, result) => {
          if (err) return res.status(500).json({ error: "Failed to process refund." });
          if (result.affectedRows === 0) {
            return res.status(400).json({ error: "No payment found to refund." });
          }

          // Notify buyer
          db.query(
            "SELECT amount FROM payments WHERE order_id = ?",
            [orderId],
            (err, paymentResults) => {
              if (!err && paymentResults.length > 0) {
                const amount = paymentResults[0].amount;
                
                createNotification(
                  order.user_id,
                  '💰 Refund Processed',
                  `Your payment of ₱${amount.toFixed(2)} for ${order.product_name} has been refunded.`,
                  'refund_processed',
                  orderId,
                  'order'
                );
              }
            }
          );

          res.json({
            message: 'Refund processed successfully.',
            status: 'refunded'
          });
        }
      );
    }
  );
});

// -------- UPDATE COMPLETE ORDER TO AUTO-RELEASE ESCROW --------
// Update your existing complete order endpoint to include this:
app.post("/api/orders/:orderId/complete", authenticateToken, (req, res) => {
  const buyerId = req.userId;
  const orderId = req.params.orderId;

  db.query(
    "SELECT * FROM orders WHERE id = ? AND user_id = ?",
    [orderId, buyerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found." });
      }

      const order = results[0];

      if (!order.seller_shipped) {
        return res.status(400).json({ error: "Seller hasn't shipped yet." });
      }

      // Complete order
      db.query(
        "UPDATE orders SET buyer_confirmed_receipt = 1, status = 'Completed', completion_date = NOW() WHERE id = ?",
        [orderId],
        (err) => {
          if (err) return res.status(500).json({ error: "Failed to complete order." });

          // ✅ AUTOMATICALLY RELEASE ESCROW
          db.query(
            `UPDATE payments 
             SET escrow_status = 'released', 
                 released_at = NOW()
             WHERE order_id = ? AND escrow_status = 'held'`,
            [orderId],
            () => {}
          );

          // Notify seller
          db.query(
            "SELECT amount FROM payments WHERE order_id = ?",
            [orderId],
            (err, paymentResults) => {
              if (!err && paymentResults.length > 0) {
                const amount = paymentResults[0].amount;
                
                createNotification(
                  order.seller_id,
                  '✅ Order Completed & Payment Released',
                  `Order for ${order.product_name} completed. Payment of ₱${amount.toFixed(2)} released from escrow.`,
                  'order_completed',
                  orderId,
                  'order'
                );
              }
            }
          );

          res.json({ 
            message: 'Order completed successfully! Payment released to seller.',
            escrow_released: true
          });
        }
      );
    }
  );
});
// ============================================
// ADMIN ROUTES
// ============================================

// -------- GET ADMIN DASHBOARD STATS --------
app.get("/api/admin/stats", isAdmin, (req, res) => {
  const statsQuery = `
    SELECT 
      (SELECT COUNT(*) FROM users) AS total_users,
      (SELECT COUNT(*) FROM users WHERE role = 'seller' AND is_approved = 0) AS pending_sellers,
      (SELECT COUNT(*) FROM users WHERE role = 'seller' AND is_approved = 1) AS approved_sellers,
      (SELECT COUNT(*) FROM products) AS total_products,
      (SELECT COUNT(*) FROM orders) AS total_orders,
      (SELECT IFNULL(SUM(price * quantity), 0) FROM orders) AS total_revenue
  `;

  db.query(statsQuery, (err, results) => {
    if (err) return res.status(500).json({ error: "Database error." });
    res.json(results[0]);
  });
});

// -------- GET PENDING SELLERS --------
app.get("/api/admin/pending-sellers", isAdmin, (req, res) => {
  db.query(
    "SELECT id, username, email, role, is_approved FROM users WHERE role = 'seller' AND is_approved = 0",
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      res.json({ sellers: results });
    }
  );
});

// -------- GET ALL USERS --------
app.get("/api/admin/users", isAdmin, (req, res) => {
  db.query(
    "SELECT id, username, email, role, is_approved, created_at FROM users ORDER BY created_at DESC",
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      res.json({ users: results });
    }
  );
});

// -------- APPROVE SELLER --------
app.post("/api/admin/approve-seller/:userId", isAdmin, (req, res) => {
  const userId = req.params.userId;

  db.query(
    "UPDATE users SET is_approved = 1 WHERE id = ? AND role = 'seller'",
    [userId],
    (err, result) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (result.affectedRows === 0) {
        return res.status(404).json({ error: "User not found or not a seller." });
      }

      db.query(
        "INSERT INTO notifications (title, message, type) VALUES (?, ?, ?)",
        ["Seller Approved", `User ID ${userId} has been approved as a seller`, "success"],
        () => {}
      );

      res.json({ message: "Seller approved successfully!" });
    }
  );
});

// -------- REJECT SELLER --------
app.post("/api/admin/reject-seller/:userId", isAdmin, (req, res) => {
  const userId = req.params.userId;

  db.query(
    "UPDATE users SET role = 'buyer', is_approved = 0 WHERE id = ?",
    [userId],
    (err, result) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (result.affectedRows === 0) {
        return res.status(404).json({ error: "User not found." });
      }
      res.json({ message: "Seller request rejected." });
    }
  );
});

// -------- DELETE PRODUCT (ADMIN) --------
app.delete("/api/admin/products/:productId", isAdmin, (req, res) => {
  const productId = req.params.productId;

  db.query(
    "DELETE FROM products WHERE id = ?",
    [productId],
    (err, result) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (result.affectedRows === 0) {
        return res.status(404).json({ error: "Product not found." });
      }
      res.json({ message: "Product deleted successfully." });
    }
  );
});

// -------- GET RECENT ACTIVITIES (ADMIN) --------
app.get("/api/admin/recent-activities", isAdmin, (req, res) => {
  const activitiesQuery = `
    (SELECT 'user_registered' as type, username as title, created_at as timestamp 
     FROM users ORDER BY created_at DESC LIMIT 5)
    UNION ALL
    (SELECT 'product_added' as type, name as title, created_at as timestamp 
     FROM products ORDER BY created_at DESC LIMIT 5)
    UNION ALL
    (SELECT 'order_placed' as type, product_name as title, created_at as timestamp 
     FROM orders ORDER BY created_at DESC LIMIT 5)
    ORDER BY timestamp DESC LIMIT 20
  `;

  db.query(activitiesQuery, (err, results) => {
    if (err) return res.status(500).json({ error: "Database error." });
    res.json({ activities: results });
  });
});

// -------- BAN/UNBAN USER (ADMIN) --------
app.post("/api/admin/toggle-ban/:userId", isAdmin, (req, res) => {
  const userId = req.params.userId;
  const { ban } = req.body;

  db.query(
    "UPDATE users SET is_banned = ? WHERE id = ?",
    [ban ? 1 : 0, userId],
    (err, result) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (result.affectedRows === 0) {
        return res.status(404).json({ error: "User not found." });
      }

      const action = ban ? "banned" : "unbanned";
      res.json({ message: `User ${action} successfully.` });
    }
  );
});

// -------- MAKE USER ADMIN (SUPER ADMIN ONLY) --------
app.post("/api/admin/make-admin/:userId", isAdmin, (req, res) => {
  const userId = req.params.userId;

  db.query(
    "UPDATE users SET is_admin = 1 WHERE id = ?",
    [userId],
    (err, result) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (result.affectedRows === 0) {
        return res.status(404).json({ error: "User not found." });
      }
      res.json({ message: "User promoted to admin successfully." });
    }
  );
});

// -------- GET SALES ANALYTICS (ADMIN) --------
app.get("/api/admin/analytics", isAdmin, (req, res) => {
  const { period } = req.query;
  
  let dateFilter = '';
  switch(period) {
    case 'week':
      dateFilter = 'WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)';
      break;
    case 'month':
      dateFilter = 'WHERE created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)';
      break;
    case 'year':
      dateFilter = 'WHERE created_at >= DATE_SUB(NOW(), INTERVAL 365 DAY)';
      break;
    default:
      dateFilter = '';
  }

  const analyticsQuery = `
    SELECT 
      DATE(created_at) as date,
      COUNT(*) as order_count,
      SUM(price * quantity) as daily_revenue
    FROM orders
    ${dateFilter}
    GROUP BY DATE(created_at)
    ORDER BY date DESC
    LIMIT 30
  `;

  db.query(analyticsQuery, (err, results) => {
    if (err) return res.status(500).json({ error: "Database error." });
    res.json({ analytics: results });
  });
});

// -------- BULK DELETE PRODUCTS (ADMIN) --------
app.post("/api/admin/products/bulk-delete", isAdmin, (req, res) => {
  const { productIds } = req.body;

  if (!Array.isArray(productIds) || productIds.length === 0) {
    return res.status(400).json({ error: "Invalid product IDs." });
  }

  const placeholders = productIds.map(() => '?').join(',');
  
  db.query(
    `DELETE FROM products WHERE id IN (${placeholders})`,
    productIds,
    (err, result) => {
      if (err) return res.status(500).json({ error: "Database error." });
      res.json({ 
        message: `${result.affectedRows} product(s) deleted successfully.`,
        deleted_count: result.affectedRows
      });
    }
  );
});

// -------- EXPORT DATA (ADMIN) --------
app.get("/api/admin/export/:type", isAdmin, (req, res) => {
  const type = req.params.type;
  
  let query = '';
  switch(type) {
    case 'users':
      query = 'SELECT id, username, email, role, is_approved, created_at FROM users';
      break;
    case 'products':
      query = 'SELECT p.*, u.username as seller_name FROM products p LEFT JOIN users u ON p.seller_id = u.id';
      break;
    case 'orders':
      query = 'SELECT o.*, u.username as buyer_name FROM orders o LEFT JOIN users u ON o.user_id = u.id';
      break;
    default:
      return res.status(400).json({ error: "Invalid export type." });
  }

  db.query(query, (err, results) => {
    if (err) return res.status(500).json({ error: "Database error." });
    res.json({ 
      data: results,
      exported_at: new Date().toISOString(),
      type: type,
      count: results.length
    });
  });
});

// -------- UPDATE ORDER STATUS (ADMIN) --------
app.put("/api/admin/orders/:orderId/status", isAdmin, (req, res) => {
  const orderId = req.params.orderId;
  const { status } = req.body;

  const validStatuses = ['Pending', 'Shipped', 'Delivered', 'Cancelled'];
  if (!validStatuses.includes(status)) {
    return res.status(400).json({ error: "Invalid status." });
  }

  db.query(
    "UPDATE orders SET status = ? WHERE id = ?",
    [status, orderId],
    (err, result) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (result.affectedRows === 0) {
        return res.status(404).json({ error: "Order not found." });
      }
      res.json({ message: "Order status updated successfully." });
    }
  );
});

// -------- FEATURE/UNFEATURE PRODUCT (ADMIN) --------
app.post("/api/admin/products/:productId/feature", isAdmin, (req, res) => {
  const productId = req.params.productId;
  const { featured } = req.body;

  db.query(
    "UPDATE products SET is_featured = ? WHERE id = ?",
    [featured ? 1 : 0, productId],
    (err, result) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (result.affectedRows === 0) {
        return res.status(404).json({ error: "Product not found." });
      }
      const action = featured ? "featured" : "unfeatured";
      res.json({ message: `Product ${action} successfully.` });
    }
  );
});

// -------- GET USER PROFILE --------
app.get("/api/profile", (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: "No token provided." });

  const token = authHeader.split(" ")[1];
  jwt.verify(token, SECRET_KEY, (err, decoded) => {
    if (err) return res.status(401).json({ error: "Invalid token." });

    db.query(
      "SELECT id, username, email, phone, address, bio, profile_image, role, is_approved, created_at FROM users WHERE id = ?",
      [decoded.id],
      (err, results) => {
        if (err) return res.status(500).json({ error: "Database error." });
        if (results.length === 0) return res.status(404).json({ error: "User not found." });
        res.json({ profile: results[0] });
      }
    );
  });
});

// -------- UPDATE USER PROFILE --------
app.put("/api/profile", upload.single('profile_image'), (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: "No token provided." });

  const token = authHeader.split(" ")[1];
  jwt.verify(token, SECRET_KEY, (err, decoded) => {
    if (err) return res.status(401).json({ error: "Invalid token." });

    const { username, email, phone, address, bio } = req.body;
    let profileImage = req.body.profile_image;

    if (req.file) {
      profileImage = `/uploads/${req.file.filename}`;
    }

    let updateFields = [];
    let updateValues = [];

    if (username) {
      updateFields.push("username = ?");
      updateValues.push(username);
    }
    if (email) {
      updateFields.push("email = ?");
      updateValues.push(email);
    }
    if (phone !== undefined) {
      updateFields.push("phone = ?");
      updateValues.push(phone);
    }
    if (address !== undefined) {
      updateFields.push("address = ?");
      updateValues.push(address);
    }
    if (bio !== undefined) {
      updateFields.push("bio = ?");
      updateValues.push(bio);
    }
    if (profileImage) {
      updateFields.push("profile_image = ?");
      updateValues.push(profileImage);
    }

    if (updateFields.length === 0) {
      return res.status(400).json({ error: "No fields to update." });
    }

    updateValues.push(decoded.id);

    db.query(
      `UPDATE users SET ${updateFields.join(", ")} WHERE id = ?`,
      updateValues,
      (err) => {
        if (err) {
          if (err.code === 'ER_DUP_ENTRY') {
            return res.status(400).json({ error: "Email already exists." });
          }
          return res.status(500).json({ error: "Failed to update profile." });
        }
        res.json({ message: "Profile updated successfully!" });
      }
    );
  });
});

// -------- CHANGE PASSWORD --------
app.post("/api/change-password", async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: "No token provided." });

  const token = authHeader.split(" ")[1];
  jwt.verify(token, SECRET_KEY, async (err, decoded) => {
    if (err) return res.status(401).json({ error: "Invalid token." });

    const { currentPassword, newPassword } = req.body;

    if (!currentPassword || !newPassword) {
      return res.status(400).json({ error: "All fields are required." });
    }

    db.query(
      "SELECT password FROM users WHERE id = ?",
      [decoded.id],
      async (err, results) => {
        if (err) return res.status(500).json({ error: "Database error." });
        if (results.length === 0) return res.status(404).json({ error: "User not found." });

        const match = await bcrypt.compare(currentPassword, results[0].password);
        if (!match) {
          return res.status(401).json({ error: "Current password is incorrect." });
        }

        const hashedPassword = await bcrypt.hash(newPassword, 10);

        db.query(
          "UPDATE users SET password = ? WHERE id = ?",
          [hashedPassword, decoded.id],
          (err) => {
            if (err) return res.status(500).json({ error: "Failed to change password." });
            res.json({ message: "Password changed successfully!" });
          }
        );
      }
    );
  });
});

// Add these routes to your server.js file

// ============================================
// CHAT SYSTEM ROUTES
// ============================================

// Middleware to verify JWT token (reuse existing or create)
function authenticateToken(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: "No token provided." });

  const token = authHeader.split(" ")[1];
  jwt.verify(token, SECRET_KEY, (err, decoded) => {
    if (err) return res.status(401).json({ error: "Invalid token." });
    req.userId = decoded.id;
    next();
  });
}

// -------- REPORT CONVERSATION --------
app.post("/api/conversations/report", authenticateToken, (req, res) => {
  const userId = req.userId;
  const { conversation_id, reason } = req.body;

  if (!conversation_id) {
    return res.status(400).json({ error: "Conversation ID is required." });
  }

  // Verify user has access to this conversation
  db.query(
    "SELECT * FROM conversations WHERE id = ? AND (user1_id = ? OR user2_id = ?)",
    [conversation_id, userId, userId],
    (err, convResults) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (convResults.length === 0) {
        return res.status(403).json({ error: "Unauthorized access to conversation." });
      }

      const conv = convResults[0];
      const reportedUserId = conv.user1_id === userId ? conv.user2_id : conv.user1_id;

      // Get reporter and reported user names
      db.query(
        "SELECT username FROM users WHERE id IN (?, ?)",
        [userId, reportedUserId],
        (err, userResults) => {
          if (err) return res.status(500).json({ error: "Database error." });

          const reporter = userResults.find(u => u.id === userId);
          const reported = userResults.find(u => u.id === reportedUserId);

          // Create notification for admin
          const notificationMessage = `Conversation reported by ${reporter?.username || 'User'} - Reason: ${reason}`;
          
          db.query(
            "INSERT INTO notifications (title, message, type) VALUES (?, ?, ?)",
            ["Conversation Reported", notificationMessage, "warning"],
            () => {}
          );

          // Mark conversation as reported (optional - add a flag to conversations table if needed)
          db.query(
            "UPDATE conversations SET is_reported = 1, report_reason = ?, reported_by = ?, reported_at = NOW() WHERE id = ?",
            [reason, userId, conversation_id],
            (err) => {
              if (err) {
                // If column doesn't exist, just return success anyway
                console.log('Report logged in notifications');
              }
              
              res.json({ 
                message: "Conversation reported to admin successfully.",
                reported: true
              });
            }
          );
        }
      );
    }
  );
});

// -------- GET USER'S CONVERSATIONS --------
app.get("/api/conversations", authenticateToken, (req, res) => {
  const userId = req.userId;

  const query = `
    SELECT 
      c.id,
      c.user1_id,
      c.user2_id,
      CASE 
        WHEN c.user1_id = ? THEN u2.username
        ELSE u1.username
      END as other_user_name,
      CASE 
        WHEN c.user1_id = ? THEN u2.role
        ELSE u1.role
      END as other_user_role,
      (SELECT message FROM messages WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1) as last_message,
      (SELECT created_at FROM messages WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1) as last_message_time,
      (SELECT COUNT(*) FROM messages WHERE conversation_id = c.id AND sender_id != ? AND is_read = 0) as unread_count
    FROM conversations c
    LEFT JOIN users u1 ON c.user1_id = u1.id
    LEFT JOIN users u2 ON c.user2_id = u2.id
    WHERE c.user1_id = ? OR c.user2_id = ?
    ORDER BY last_message_time DESC
  `;

  db.query(query, [userId, userId, userId, userId, userId], (err, results) => {
    if (err) return res.status(500).json({ error: "Database error." });
    res.json({ conversations: results });
  });
});

// -------- GET MESSAGES IN A CONVERSATION --------
app.get("/api/messages/:conversationId", authenticateToken, (req, res) => {
  const conversationId = req.params.conversationId;
  const userId = req.userId;

  // First verify user has access to this conversation
  db.query(
    "SELECT * FROM conversations WHERE id = ? AND (user1_id = ? OR user2_id = ?)",
    [conversationId, userId, userId],
    (err, convResults) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (convResults.length === 0) {
        return res.status(403).json({ error: "Unauthorized access to conversation." });
      }

      // Mark messages as read
      db.query(
        "UPDATE messages SET is_read = 1 WHERE conversation_id = ? AND sender_id != ?",
        [conversationId, userId],
        () => {}
      );

      // Get messages
      const query = `
        SELECT 
          m.*,
          u.username as sender_name,
          u.role as sender_role
        FROM messages m
        LEFT JOIN users u ON m.sender_id = u.id
        WHERE m.conversation_id = ?
        ORDER BY m.created_at ASC
      `;

      db.query(query, [conversationId], (err, results) => {
        if (err) return res.status(500).json({ error: "Database error." });
        res.json({ messages: results });
      });
    }
  );
});

// -------- CREATE NEW CONVERSATION --------
app.post("/api/conversations", authenticateToken, (req, res) => {
  const userId = req.userId;
  const { recipient } = req.body;

  if (!recipient) {
    return res.status(400).json({ error: "Recipient is required." });
  }

  // Find recipient user
  db.query(
    "SELECT id FROM users WHERE username = ? OR email = ?",
    [recipient, recipient],
    (err, userResults) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (userResults.length === 0) {
        return res.status(404).json({ error: "User not found." });
      }

      const recipientId = userResults[0].id;

      if (recipientId === userId) {
        return res.status(400).json({ error: "Cannot start conversation with yourself." });
      }

      // Check if conversation already exists
      db.query(
        "SELECT id FROM conversations WHERE (user1_id = ? AND user2_id = ?) OR (user1_id = ? AND user2_id = ?)",
        [userId, recipientId, recipientId, userId],
        (err, convResults) => {
          if (err) return res.status(500).json({ error: "Database error." });

          if (convResults.length > 0) {
            return res.json({
              conversation_id: convResults[0].id,
              message: "Conversation already exists.",
            });
          }

          // Create new conversation
          db.query(
            "INSERT INTO conversations (user1_id, user2_id) VALUES (?, ?)",
            [userId, recipientId],
            (err, result) => {
              if (err) return res.status(500).json({ error: "Database error." });
              res.status(201).json({
                conversation_id: result.insertId,
                message: "Conversation created successfully.",
              });
            }
          );
        }
      );
    }
  );
});

// -------- SEND MESSAGE --------
app.post("/api/messages", authenticateToken, (req, res) => {
  const senderId = req.userId;
  const { conversation_id, message } = req.body;

  if (!conversation_id || !message) {
    return res.status(400).json({ error: "Conversation ID and message are required." });
  }

  // Verify user has access to conversation
  db.query(
    "SELECT * FROM conversations WHERE id = ? AND (user1_id = ? OR user2_id = ?)",
    [conversation_id, senderId, senderId],
    (err, convResults) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (convResults.length === 0) {
        return res.status(403).json({ error: "Unauthorized access to conversation." });
      }

      // Insert message
      db.query(
        "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
        [conversation_id, senderId, message],
        (err, result) => {
          if (err) return res.status(500).json({ error: "Database error." });
          res.status(201).json({
            message_id: result.insertId,
            message: "Message sent successfully.",
          });
        }
      );
    }
  );
});

// -------- GET ALL CONVERSATIONS (ADMIN ONLY) --------
app.get("/api/admin/all-conversations", isAdmin, (req, res) => {
  const query = `
    SELECT 
      c.id,
      c.user1_id,
      c.user2_id,
      u1.username as user1_name,
      u1.role as user1_role,
      u2.username as user2_name,
      u2.role as user2_role,
      (SELECT message FROM messages WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1) as last_message,
      (SELECT created_at FROM messages WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1) as last_message_time,
      (SELECT COUNT(*) FROM messages WHERE conversation_id = c.id) as message_count
    FROM conversations c
    LEFT JOIN users u1 ON c.user1_id = u1.id
    LEFT JOIN users u2 ON c.user2_id = u2.id
    ORDER BY last_message_time DESC
  `;

  db.query(query, (err, results) => {
    if (err) return res.status(500).json({ error: "Database error." });
    res.json({ conversations: results });
  });
});

// -------- DELETE CONVERSATION (ADMIN) --------
app.delete("/api/admin/conversations/:conversationId", isAdmin, (req, res) => {
  const conversationId = req.params.conversationId;

  // Delete messages first
  db.query(
    "DELETE FROM messages WHERE conversation_id = ?",
    [conversationId],
    (err) => {
      if (err) return res.status(500).json({ error: "Database error." });

      // Delete conversation
      db.query(
        "DELETE FROM conversations WHERE id = ?",
        [conversationId],
        (err, result) => {
          if (err) return res.status(500).json({ error: "Database error." });
          if (result.affectedRows === 0) {
            return res.status(404).json({ error: "Conversation not found." });
          }
          res.json({ message: "Conversation deleted successfully." });
        }
      );
    }
  );
});

// Add these routes to your server.js file

// ============================================
// PASSWORD RESET ROUTES
// ============================================

// Store for reset codes (in production, use Redis or database)
const resetCodes = new Map();

// Generate random 6-digit code
function generateResetCode() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

// -------- REQUEST PASSWORD RESET --------
app.post("/api/forgot-password", async (req, res) => {
  const { email } = req.body;

  if (!email) {
    return res.status(400).json({ error: "Email is required." });
  }

  try {
    // Check if user exists
    db.query(
      "SELECT id, username, email FROM users WHERE email = ?",
      [email],
      (err, results) => {
        if (err) return res.status(500).json({ error: "Database error." });
        if (results.length === 0) {
          return res.status(404).json({ error: "Email not found." });
        }

        const user = results[0];
        const resetCode = generateResetCode();
        
        // Store code with expiry (10 minutes)
        resetCodes.set(email, {
          code: resetCode,
          userId: user.id,
          expiresAt: Date.now() + 10 * 60 * 1000, // 10 minutes
        });

        // In production, send email here
        console.log(`Reset code for ${email}: ${resetCode}`);

        // For development, return code in response
        // Remove this in production!
        res.json({
          message: "Reset code sent successfully.",
          // DEV ONLY - Remove in production
          devCode: resetCode,
        });
      }
    );
  } catch (e) {
    res.status(500).json({ error: "Server error." });
  }
});

// -------- RESET PASSWORD WITH CODE --------
app.post("/api/reset-password", async (req, res) => {
  const { email, code, newPassword } = req.body;

  if (!email || !code || !newPassword) {
    return res.status(400).json({ error: "All fields are required." });
  }

  if (newPassword.length < 6) {
    return res.status(400).json({ error: "Password must be at least 6 characters." });
  }

  try {
    // Check if code exists and is valid
    const resetData = resetCodes.get(email);

    if (!resetData) {
      return res.status(400).json({ error: "Invalid or expired reset code." });
    }

    if (Date.now() > resetData.expiresAt) {
      resetCodes.delete(email);
      return res.status(400).json({ error: "Reset code has expired." });
    }

    if (resetData.code !== code) {
      return res.status(400).json({ error: "Invalid reset code." });
    }

    // Hash new password
    const hashedPassword = await bcrypt.hash(newPassword, 10);

    // Update password
    db.query(
      "UPDATE users SET password = ? WHERE email = ?",
      [hashedPassword, email],
      (err, result) => {
        if (err) return res.status(500).json({ error: "Database error." });

        // Delete used code
        resetCodes.delete(email);

        // Add notification
        db.query(
          "INSERT INTO notifications (title, message, type) VALUES (?, ?, ?)",
          [
            "Password Reset",
            `Password was reset for ${email}`,
            "success",
          ],
          () => {}
        );

        res.json({ message: "Password reset successfully." });
      }
    );
  } catch (e) {
    res.status(500).json({ error: "Server error." });
  }
});

// -------- VERIFY RESET CODE --------
app.post("/api/verify-reset-code", (req, res) => {
  const { email, code } = req.body;

  if (!email || !code) {
    return res.status(400).json({ error: "Email and code are required." });
  }

  const resetData = resetCodes.get(email);

  if (!resetData) {
    return res.status(400).json({ valid: false, error: "Invalid or expired code." });
  }

  if (Date.now() > resetData.expiresAt) {
    resetCodes.delete(email);
    return res.status(400).json({ valid: false, error: "Code has expired." });
  }

  if (resetData.code !== code) {
    return res.status(400).json({ valid: false, error: "Invalid code." });
  }

  res.json({ valid: true, message: "Code verified successfully." });
});

// Clean up expired codes every 30 minutes
setInterval(() => {
  const now = Date.now();
  for (const [email, data] of resetCodes.entries()) {
    if (now > data.expiresAt) {
      resetCodes.delete(email);
    }
  }
}, 30 * 60 * 1000);

app.post("/api/orders/create", authenticateToken, async (req, res) => {
  const buyerId = req.userId;
  const { product_id, quantity, message } = req.body;

  console.log('📦 Order Creation Request:');
  console.log('  Buyer ID:', buyerId);
  console.log('  Product ID:', product_id);
  console.log('  Quantity:', quantity);

  if (!product_id || !quantity) {
    return res.status(400).json({ error: "Product ID and quantity are required." });
  }

  try {
    // Get product details
    db.query(
      "SELECT * FROM products WHERE id = ?",
      [product_id],
      async (err, productResults) => {
        if (err) return res.status(500).json({ error: "Database error." });
        if (productResults.length === 0) {
          return res.status(404).json({ error: "Product not found." });
        }

        const product = productResults[0];

        if (!product.seller_id) {
          return res.status(400).json({ 
            error: "This product has no seller assigned." 
          });
        }

        // ✅ CHECK STOCK AVAILABILITY
        const requestedQty = parseInt(quantity);
        const currentStock = product.stock ? parseFloat(product.stock) : 0;

        console.log('📊 Stock Check:');
        console.log('  Current Stock:', currentStock);
        console.log('  Requested Qty:', requestedQty);

        if (product.stock && currentStock < requestedQty) {
          console.log('❌ Insufficient stock');
          return res.status(400).json({ 
            error: `Only ${currentStock} ${product.unit || 'items'} available in stock.` 
          });
        }

        const totalPrice = parseFloat(product.price) * requestedQty;

        // Check or create conversation
        db.query(
          `SELECT id FROM conversations 
           WHERE (user1_id = ? AND user2_id = ?) 
           OR (user1_id = ? AND user2_id = ?)`,
          [buyerId, product.seller_id, product.seller_id, buyerId],
          (err, convResults) => {
            if (err) return res.status(500).json({ error: "Database error." });

            const createOrderAndNotify = (convId) => {
              // ✅ DEDUCT STOCK WHEN ORDER IS PLACED
              const newStock = currentStock - requestedQty;
              
              console.log('🔄 Deducting stock:', currentStock, '-', requestedQty, '=', newStock);

              // Update product stock
              db.query(
                "UPDATE products SET stock = ? WHERE id = ?",
                [newStock, product_id],
                (err) => {
                  if (err) {
                    console.log('❌ Failed to update stock:', err);
                    return res.status(500).json({ error: "Failed to update stock." });
                  }

                  console.log('✅ Stock updated successfully');

                  // Create order with stock snapshot
                  const insertQuery = `
                    INSERT INTO orders 
                    (user_id, seller_id, product_id, product_name, quantity, price, 
                     status, seller_confirmed, seller_shipped, buyer_confirmed_receipt, 
                     dispute_raised, can_cancel_buyer, conversation_id) 
                    VALUES (?, ?, ?, ?, ?, ?, 'Pending', 0, 0, 0, 0, 1, ?)
                  `;
                  
                  db.query(
                    insertQuery,
                    [buyerId, product.seller_id, product_id, product.name, requestedQty, totalPrice, convId],
                    (err, orderResult) => {
                      if (err) {
                        // ⚠️ ROLLBACK: Restore stock if order creation fails
                        db.query(
                          "UPDATE products SET stock = ? WHERE id = ?",
                          [currentStock, product_id],
                          () => {}
                        );
                        return res.status(500).json({ error: "Failed to create order." });
                      }

                      const orderId = orderResult.insertId;
                      console.log('✅ Order created:', orderId);

                      // Create notification for seller
                      const notificationMessage = `New order for ${product.name} (Qty: ${requestedQty}) - Total: ₱${totalPrice.toFixed(2)}`;
                      
                      db.query(
                        `INSERT INTO user_notifications (user_id, title, message, type, reference_id, reference_type) 
                         VALUES (?, ?, ?, ?, ?, ?)`,
                        [product.seller_id, 'New Order Request', notificationMessage, 'new_order', orderId, 'order'],
                        () => {}
                      );

                      // Send automatic message
                      if (convId) {
                        const autoMessage = `🛒 New Order Request\n\nProduct: ${product.name}\nQuantity: ${requestedQty}\nTotal: ₱${totalPrice.toFixed(2)}\n\n${message || 'Please confirm this order.'}`;
                        
                        db.query(
                          "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
                          [convId, buyerId, autoMessage],
                          () => {}
                        );
                      }

                      res.status(201).json({
                        message: "Order placed successfully! Waiting for seller confirmation.",
                        order_id: orderId,
                        conversation_id: convId,
                        stock_remaining: newStock
                      });
                    }
                  );
                }
              );
            };

            if (convResults.length > 0) {
              createOrderAndNotify(convResults[0].id);
            } else {
              db.query(
                "INSERT INTO conversations (user1_id, user2_id) VALUES (?, ?)",
                [buyerId, product.seller_id],
                (err, newConvResult) => {
                  if (err) return res.status(500).json({ error: "Failed to create conversation." });
                  createOrderAndNotify(newConvResult.insertId);
                }
              );
            }
          }
        );
      }
    );
  } catch (e) {
    console.log('❌ Server error:', e);
    res.status(500).json({ error: "Server error." });
  }
});

app.get("/api/seller/all-orders", authenticateToken, (req, res) => {
  const sellerId = req.userId;

  db.query(
    `SELECT o.*, 
            u.username as buyer_name, 
            u.email as buyer_email, 
            p.image_url as product_image
     FROM orders o
     LEFT JOIN users u ON o.user_id = u.id
     LEFT JOIN products p ON o.product_id = p.id
     WHERE o.seller_id = ?
     ORDER BY o.created_at DESC`,
    [sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      res.json({ orders: results });
    }
  );
});
// -------- SELLER CONFIRM ORDER --------
app.post("/api/orders/:orderId/confirm", authenticateToken, (req, res) => {
  const sellerId = req.userId;
  const orderId = req.params.orderId;

  // Verify seller owns this order
  db.query(
    "SELECT * FROM orders WHERE id = ? AND seller_id = ?",
    [orderId, sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];

      if (order.seller_confirmed === 1) {
        return res.status(400).json({ error: "Order already confirmed." });
      }

      // Update order - confirm and lock buyer cancellation
      db.query(
        "UPDATE orders SET seller_confirmed = 1, can_cancel_buyer = 0, status = 'Confirmed' WHERE id = ?",
        [orderId],
        (err) => {
          if (err) return res.status(500).json({ error: "Failed to confirm order." });

          // Notify buyer
          const notificationMessage = `Your order for ${order.product_name} has been confirmed by the seller.`;
          db.query(
            "INSERT INTO order_notifications (order_id, recipient_id, type, message) VALUES (?, ?, 'order_confirmed', ?)",
            [orderId, order.user_id, notificationMessage],
            () => {}
          );

          // Send message to conversation
          if (order.conversation_id) {
            const confirmMessage = `✅ Order Confirmed\n\nYour order for ${order.product_name} (Qty: ${order.quantity}) has been confirmed!\nTotal: ₱${order.price}`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, sellerId, confirmMessage],
              () => {}
            );
          }

          res.json({ message: "Order confirmed successfully!" });
        }
      );
    }
  );
});

app.post("/api/orders/:orderId/seller-cancel-accepted", authenticateToken, (req, res) => {
  const sellerId = req.userId;
  const orderId = req.params.orderId;
  const { reason } = req.body;

  console.log('❌ Cancel order request:', orderId);

  db.query(
    "SELECT * FROM orders WHERE id = ? AND seller_id = ?",
    [orderId, sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];

      // Can't cancel after shipping
      if (order.seller_shipped === 1) {
        return res.status(400).json({ error: "Cannot cancel after marking as shipped." });
      }

      // ✅ RESTORE STOCK TO PRODUCT
      if (order.product_id && order.quantity) {
        db.query(
          "UPDATE products SET stock = stock + ? WHERE id = ?",
          [order.quantity, order.product_id],
          (err) => {
            if (err) {
              console.log('⚠️ Failed to restore stock:', err);
            } else {
              console.log('✅ Stock restored:', order.quantity, 'units');
            }
          }
        );
      }

      // Cancel order
      db.query(
        "UPDATE orders SET status = 'Cancelled' WHERE id = ?",
        [orderId],
        (err) => {
          if (err) return res.status(500).json({ error: "Failed to cancel order." });

          console.log('✅ Order cancelled');

          // Return product to marketplace
          if (order.product_id) {
            db.query(
              "UPDATE products SET status = 'available' WHERE id = ?",
              [order.product_id],
              () => {}
            );
          }

          // ✅ FIX: Get payment amount safely
          db.query(
            "SELECT amount FROM payments WHERE order_id = ?",
            [orderId],
            (err, paymentResults) => {
              let refundText = '';
              if (!err && paymentResults.length > 0) {
                const amount = parseFloat(paymentResults[0].amount) || 0;
                if (amount > 0) {
                  refundText = ` Your payment of ₱${amount.toFixed(2)} will be refunded.`;
                }
              }

              // Notify buyer with refund info
              createNotification(
                order.user_id,
                'Order Cancelled - Stock Restored',
                `Your order for ${order.product_name} has been cancelled. ${order.quantity} ${order.unit || 'items'} restored to stock.${reason ? ' Reason: ' + reason : ''}${refundText}`,
                'order_cancelled',
                orderId,
                'order'
              );

              // Send message
              if (order.conversation_id) {
                const cancelMsg = `❌ Order Cancelled\n\nSeller cancelled the order for ${order.product_name}.\n\n📦 ${order.quantity} ${order.unit || 'items'} restored to stock.${reason ? '\n\nReason: ' + reason : ''}${refundText}`;
                
                db.query(
                  "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
                  [order.conversation_id, sellerId, cancelMsg],
                  () => {}
                );
              }

              res.json({ 
                message: "Order cancelled. Stock restored to product.",
                stock_restored: order.quantity
              });
            }
          );
        }
      );
    }
  );
});


// -------- GET ORDER NOTIFICATIONS --------
app.get("/api/order-notifications", authenticateToken, (req, res) => {
  const userId = req.userId;

  db.query(
    `SELECT on.*, o.product_name, o.quantity, o.price, o.status, o.seller_confirmed
     FROM order_notifications on
     LEFT JOIN orders o ON on.order_id = o.id
     WHERE on.recipient_id = ?
     ORDER BY on.created_at DESC
     LIMIT 50`,
    [userId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      res.json({ notifications: results });
    }
  );
});

// -------- MARK NOTIFICATION AS READ --------
app.post("/api/order-notifications/:notificationId/read", authenticateToken, (req, res) => {
  const userId = req.userId;
  const notificationId = req.params.notificationId;

  db.query(
    "UPDATE order_notifications SET is_read = 1 WHERE id = ? AND recipient_id = ?",
    [notificationId, userId],
    (err, result) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (result.affectedRows === 0) {
        return res.status(404).json({ error: "Notification not found." });
      }
      res.json({ message: "Notification marked as read." });
    }
  );
});

// -------- GET UNREAD NOTIFICATION COUNT --------
app.get("/api/order-notifications/unread/count", authenticateToken, (req, res) => {
  const userId = req.userId;

  db.query(
    "SELECT COUNT(*) as count FROM order_notifications WHERE recipient_id = ? AND is_read = 0",
    [userId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      res.json({ unread_count: results[0].count });
    }
  );
});

// -------- GET ORDER DETAILS WITH STATUS --------
app.get("/api/orders/:orderId", authenticateToken, (req, res) => {
  const userId = req.userId;
  const orderId = req.params.orderId;

  db.query(
    `SELECT o.*, 
            u1.username as buyer_name, u1.email as buyer_email,
            u2.username as seller_name, u2.email as seller_email,
            p.name as product_name, p.image_url as product_image
     FROM orders o
     LEFT JOIN users u1 ON o.user_id = u1.id
     LEFT JOIN users u2 ON o.seller_id = u2.id
     LEFT JOIN products p ON o.product_id = p.id
     WHERE o.id = ? AND (o.user_id = ? OR o.seller_id = ?)`,
    [orderId, userId, userId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found." });
      }
      res.json({ order: results[0] });
    }
  );
});

// -------- GET SELLER'S PENDING ORDERS --------
app.get("/api/seller/pending-orders", authenticateToken, (req, res) => {
  const sellerId = req.userId;

  db.query(
    `SELECT o.*, u.username as buyer_name, u.email as buyer_email, p.image_url as product_image
     FROM orders o
     LEFT JOIN users u ON o.user_id = u.id
     LEFT JOIN products p ON o.product_id = p.id
     WHERE o.seller_id = ? AND o.seller_confirmed = 0 AND o.status != 'Cancelled'
     ORDER BY o.created_at DESC`,
    [sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      res.json({ pending_orders: results });
    }
  );
});

// -------- UPDATE ORDER STATUS (SELLER) --------
app.put("/api/orders/:orderId/status", authenticateToken, (req, res) => {
  const sellerId = req.userId;
  const orderId = req.params.orderId;
  const { status } = req.body;

  const validStatuses = ['Confirmed', 'Shipped', 'Delivered'];
  if (!validStatuses.includes(status)) {
    return res.status(400).json({ error: "Invalid status." });
  }

  db.query(
    "SELECT * FROM orders WHERE id = ? AND seller_id = ?",
    [orderId, sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];

      db.query(
        "UPDATE orders SET status = ? WHERE id = ?",
        [status, orderId],
        (err) => {
          if (err) return res.status(500).json({ error: "Failed to update status." });

          // Notify buyer
          const notificationMessage = `Your order for ${order.product_name} status: ${status}`;
          db.query(
            "INSERT INTO order_notifications (order_id, recipient_id, type, message) VALUES (?, ?, ?, ?)",
            [orderId, order.user_id, `order_${status.toLowerCase()}`, notificationMessage],
            () => {}
          );

          // Send message
          if (order.conversation_id) {
            const statusMessage = `📦 Order Status Update\n\nYour order for ${order.product_name} is now: ${status}`;
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, sellerId, statusMessage],
              () => {}
            );
          }

          res.json({ message: "Order status updated successfully!" });
        }
      );
    }
  );
});

// -------- REPORT CONVERSATION --------
app.post("/api/conversations/report", authenticateToken, (req, res) => {
  const userId = req.userId;
  const { conversation_id, reason } = req.body;

  if (!conversation_id) {
    return res.status(400).json({ error: "Conversation ID is required." });
  }

  // Verify user has access to this conversation
  db.query(
    "SELECT * FROM conversations WHERE id = ? AND (user1_id = ? OR user2_id = ?)",
    [conversation_id, userId, userId],
    (err, convResults) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (convResults.length === 0) {
        return res.status(403).json({ error: "Unauthorized access to conversation." });
      }

      const conv = convResults[0];
      const reportedUserId = conv.user1_id === userId ? conv.user2_id : conv.user1_id;

      // Get reporter and reported user names
      db.query(
        "SELECT id, username FROM users WHERE id IN (?, ?)",
        [userId, reportedUserId],
        (err, userResults) => {
          if (err) return res.status(500).json({ error: "Database error." });

          const reporter = userResults.find(u => u.id === userId);
          const reported = userResults.find(u => u.id === reportedUserId);

          // Create notification for admin
          const notificationMessage = `Conversation #${conversation_id} reported by ${reporter?.username || 'User'} against ${reported?.username || 'User'}. Reason: ${reason || 'No reason provided'}`;
          
          db.query(
            "INSERT INTO notifications (title, message, type) VALUES (?, ?, ?)",
            ["⚠️ Conversation Reported", notificationMessage, "warning"],
            (err) => {
              if (err) console.error('Error creating notification:', err);
            }
          );

          // Mark conversation as reported
          db.query(
            "UPDATE conversations SET is_reported = 1, report_reason = ?, reported_by = ?, reported_at = NOW() WHERE id = ?",
            [reason || 'No reason provided', userId, conversation_id],
            (err) => {
              if (err) {
                console.error('Error updating conversation:', err);
                return res.status(500).json({ error: "Failed to mark conversation as reported." });
              }
              
              res.json({ 
                message: "Conversation reported to admin successfully.",
                reported: true
              });
            }
          );
        }
      );
    }
  );
});

// -------- SELLER ACCEPT ORDER --------
app.post("/api/orders/:orderId/accept", authenticateToken, (req, res) => {
  const sellerId = req.userId;
  const orderId = req.params.orderId;

  // Verify seller owns this order
  db.query(
    "SELECT * FROM orders WHERE id = ? AND seller_id = ?",
    [orderId, sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];

      // Update order status to accepted
      db.query(
        "UPDATE orders SET status = 'Accepted', seller_confirmed = 1, can_cancel_buyer = 0 WHERE id = ?",
        [orderId],
        (err) => {
          if (err) return res.status(500).json({ error: "Failed to accept order." });

          // Notify buyer
          const notificationMessage = `Your order for ${order.product_name} has been accepted by the seller.`;
          db.query(
            "INSERT INTO order_notifications (order_id, recipient_id, type, message) VALUES (?, ?, 'order_accepted', ?)",
            [orderId, order.user_id, notificationMessage],
            () => {}
          );

          // Send message to conversation
          if (order.conversation_id) {
            const acceptMessage = `✅ Order Accepted\n\nYour order for ${order.product_name} (Qty: ${order.quantity}) has been accepted!\nTotal: ₱${order.price}`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, sellerId, acceptMessage],
              () => {}
            );
          }

          res.json({ message: "Order accepted successfully!" });
        }
      );
    }
  );
});

// -------- SELLER CANCEL ORDER (Returns to marketplace) --------
app.post("/api/orders/:orderId/seller-cancel", authenticateToken, (req, res) => {
  const sellerId = req.userId;
  const orderId = req.params.orderId;
  const { reason } = req.body;

  db.query(
    "SELECT * FROM orders WHERE id = ? AND seller_id = ?",
    [orderId, sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];

      // Cancel order and make product available again
      db.query(
        "UPDATE orders SET status = 'Cancelled' WHERE id = ?",
        [orderId],
        (err) => {
          if (err) return res.status(500).json({ error: "Failed to cancel order." });

          // Update product status back to available if needed
          if (order.product_id) {
            db.query(
              "UPDATE products SET status = 'available' WHERE id = ?",
              [order.product_id],
              () => {}
            );
          }

          // Notify buyer
          const cancelMessage = `Order for ${order.product_name} was cancelled by seller.${reason ? ' Reason: ' + reason : ''}`;
          db.query(
            "INSERT INTO order_notifications (order_id, recipient_id, type, message) VALUES (?, ?, 'order_cancelled', ?)",
            [orderId, order.user_id, cancelMessage],
            () => {}
          );

          // Send message to conversation
          if (order.conversation_id) {
            const msgText = `❌ Order Cancelled\n\nSeller cancelled the order for ${order.product_name}.${reason ? '\n\nReason: ' + reason : ''}\n\nThe product is now available again in the marketplace.`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, sellerId, msgText],
              () => {}
            );
          }

          res.json({ message: "Order cancelled. Product returned to marketplace." });
        }
      );
    }
  );
});

// -------- GET UNREAD ORDER NOTIFICATIONS COUNT --------
app.get("/api/seller/unread-orders-count", authenticateToken, (req, res) => {
  const sellerId = req.userId;

  db.query(
    `SELECT COUNT(*) as count 
     FROM orders 
     WHERE seller_id = ? AND seller_confirmed = 0 AND status != 'Cancelled'`,
    [sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      res.json({ unread_count: results[0].count });
    }
  );
});

// -------- GET LATEST PENDING ORDER FOR POPUP --------
app.get("/api/seller/latest-pending-order", authenticateToken, (req, res) => {
  const sellerId = req.userId;

  db.query(
    `SELECT o.*, u.username as buyer_name, u.email as buyer_email, 
            p.name as product_name, p.image_url as product_image
     FROM orders o
     LEFT JOIN users u ON o.user_id = u.id
     LEFT JOIN products p ON o.product_id = p.id
     WHERE o.seller_id = ? AND o.seller_confirmed = 0 AND o.status != 'Cancelled'
     AND o.notification_shown = 0
     ORDER BY o.created_at DESC
     LIMIT 1`,
    [sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      
      if (results.length > 0) {
        // Mark as shown
        db.query(
          "UPDATE orders SET notification_shown = 1 WHERE id = ?",
          [results[0].id],
          () => {}
        );
        
        res.json({ 
          has_new_order: true,
          order: results[0] 
        });
      } else {
        res.json({ has_new_order: false });
      }
    }
  );
});

// Add these to server.js after existing order routes:

// -------- GET LATEST PENDING ORDER FOR POPUP --------
app.get("/api/seller/latest-pending-order", authenticateToken, (req, res) => {
  const sellerId = req.userId;

  db.query(
    `SELECT o.*, u.username as buyer_name, u.email as buyer_email, 
            p.name as product_name, p.image_url as product_image
     FROM orders o
     LEFT JOIN users u ON o.user_id = u.id
     LEFT JOIN products p ON o.product_id = p.id
     WHERE o.seller_id = ? AND o.seller_confirmed = 0 AND o.status != 'Cancelled'
     AND o.notification_shown = 0
     ORDER BY o.created_at DESC
     LIMIT 1`,
    [sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      
      if (results.length > 0) {
        // Mark as shown
        db.query(
          "UPDATE orders SET notification_shown = 1 WHERE id = ?",
          [results[0].id],
          () => {}
        );
        
        res.json({ 
          has_new_order: true,
          order: results[0] 
        });
      } else {
        res.json({ has_new_order: false });
      }
    }
  );
});

// -------- SELLER ACCEPT ORDER --------
app.post("/api/orders/:orderId/accept", authenticateToken, (req, res) => {
  const sellerId = req.userId;
  const orderId = req.params.orderId;

  db.query(
    "SELECT * FROM orders WHERE id = ? AND seller_id = ?",
    [orderId, sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];

      db.query(
        "UPDATE orders SET status = 'Accepted', seller_confirmed = 1, can_cancel_buyer = 0 WHERE id = ?",
        [orderId],
        (err) => {
          if (err) return res.status(500).json({ error: "Failed to accept order." });

          // Notify buyer
          const notificationMessage = `Your order for ${order.product_name} has been accepted by the seller.`;
          db.query(
            "INSERT INTO order_notifications (order_id, recipient_id, type, message) VALUES (?, ?, 'order_accepted', ?)",
            [orderId, order.user_id, notificationMessage],
            () => {}
          );

          // Send message to conversation
          if (order.conversation_id) {
            const acceptMessage = `✅ Order Accepted\n\nYour order for ${order.product_name} (Qty: ${order.quantity}) has been accepted!\nTotal: ₱${order.price}`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, sellerId, acceptMessage],
              () => {}
            );
          }

          res.json({ message: "Order accepted successfully!" });
        }
      );
    }
  );
});

// -------- SELLER CANCEL ORDER (Returns to marketplace) --------
app.post("/api/orders/:orderId/seller-cancel", authenticateToken, (req, res) => {
  const sellerId = req.userId;
  const orderId = req.params.orderId;
  const { reason } = req.body;

  db.query(
    "SELECT * FROM orders WHERE id = ? AND seller_id = ?",
    [orderId, sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];

      db.query(
        "UPDATE orders SET status = 'Cancelled' WHERE id = ?",
        [orderId],
        (err) => {
          if (err) return res.status(500).json({ error: "Failed to cancel order." });

          // Update product status back to available
          if (order.product_id) {
            db.query(
              "UPDATE products SET status = 'available' WHERE id = ?",
              [order.product_id],
              () => {}
            );
          }

          // Notify buyer
          const cancelMessage = `Order for ${order.product_name} was cancelled by seller.${reason ? ' Reason: ' + reason : ''}`;
          db.query(
            "INSERT INTO order_notifications (order_id, recipient_id, type, message) VALUES (?, ?, 'order_cancelled', ?)",
            [orderId, order.user_id, cancelMessage],
            () => {}
          );

          // Send message to conversation
          if (order.conversation_id) {
            const msgText = `❌ Order Cancelled\n\nSeller cancelled the order for ${order.product_name}.${reason ? '\n\nReason: ' + reason : ''}\n\nThe product is now available again in the marketplace.`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, sellerId, msgText],
              () => {}
            );
          }

          res.json({ message: "Order cancelled. Product returned to marketplace." });
        }
      );
    }
  );
});


// -------- START SERVER --------
app.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 Server running on http://0.0.0.0:${PORT}`);
  console.log(`📱 Flutter should connect to: http://10.0.2.2:${PORT} (Android)`);
  console.log(`🖼️ Images saved to: ${uploadsDir}`);
});

app.get("/api/user/notifications", authenticateToken, (req, res) => {
  const userId = req.userId;
  const { unread_only } = req.query;

  let query = `
    SELECT * FROM user_notifications 
    WHERE user_id = ?
  `;

  if (unread_only === 'true') {
    query += ' AND is_read = 0';
  }

  query += ' ORDER BY created_at DESC LIMIT 50';

  db.query(query, [userId], (err, results) => {
    if (err) return res.status(500).json({ error: "Database error." });
    res.json({ notifications: results });
  });
});

// -------- GET UNREAD NOTIFICATION COUNT --------
app.get("/api/user/notifications/unread-count", authenticateToken, (req, res) => {
  const userId = req.userId;

  db.query(
    "SELECT COUNT(*) as count FROM user_notifications WHERE user_id = ? AND is_read = 0",
    [userId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      res.json({ unread_count: results[0].count });
    }
  );
});

// -------- MARK NOTIFICATION AS READ --------
app.post("/api/user/notifications/:notificationId/read", authenticateToken, (req, res) => {
  const userId = req.userId;
  const notificationId = req.params.notificationId;

  db.query(
    "UPDATE user_notifications SET is_read = 1, read_at = NOW() WHERE id = ? AND user_id = ?",
    [notificationId, userId],
    (err, result) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (result.affectedRows === 0) {
        return res.status(404).json({ error: "Notification not found." });
      }
      res.json({ message: "Notification marked as read." });
    }
  );
});

// -------- MARK ALL NOTIFICATIONS AS READ --------
app.post("/api/user/notifications/read-all", authenticateToken, (req, res) => {
  const userId = req.userId;

  db.query(
    "UPDATE user_notifications SET is_read = 1, read_at = NOW() WHERE user_id = ? AND is_read = 0",
    [userId],
    (err, result) => {
      if (err) return res.status(500).json({ error: "Database error." });
      res.json({ 
        message: "All notifications marked as read.",
        count: result.affectedRows 
      });
    }
  );
});

// -------- DELETE NOTIFICATION --------
app.delete("/api/user/notifications/:notificationId", authenticateToken, (req, res) => {
  const userId = req.userId;
  const notificationId = req.params.notificationId;

  db.query(
    "DELETE FROM user_notifications WHERE id = ? AND user_id = ?",
    [notificationId, userId],
    (err, result) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (result.affectedRows === 0) {
        return res.status(404).json({ error: "Notification not found." });
      }
      res.json({ message: "Notification deleted." });
    }
  );
});

// -------- CLEAR ALL READ NOTIFICATIONS --------
app.delete("/api/user/notifications/clear-read", authenticateToken, (req, res) => {
  const userId = req.userId;

  db.query(
    "DELETE FROM user_notifications WHERE user_id = ? AND is_read = 1",
    [userId],
    (err, result) => {
      if (err) return res.status(500).json({ error: "Database error." });
      res.json({ 
        message: "Read notifications cleared.",
        count: result.affectedRows 
      });
    }
  );
});

// -------- HELPER FUNCTION: CREATE NOTIFICATION --------
function createNotification(userId, title, message, type, referenceId = null, referenceType = null) {
  db.query(
    `INSERT INTO user_notifications (user_id, title, message, type, reference_id, reference_type) 
     VALUES (?, ?, ?, ?, ?, ?)`,
    [userId, title, message, type, referenceId, referenceType],
    (err) => {
      if (err) console.error('Error creating notification:', err);
    }
  );
}
// -------- UPDATE UNREPORT CONVERSATION ENDPOINT --------
app.post("/api/admin/conversations/:conversationId/unreport", isAdmin, (req, res) => {
  const conversationId = req.params.conversationId;

  db.query(
    "UPDATE conversations SET is_reported = 0, report_reason = NULL, reported_by = NULL, reported_at = NULL WHERE id = ?",
    [conversationId],
    (err, result) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (result.affectedRows === 0) {
        return res.status(404).json({ error: "Conversation not found." });
      }
      res.json({ message: "Report dismissed successfully." });
    }
  );
});

// -------- UPDATE ORDER CREATION TO USE NEW NOTIFICATION SYSTEM --------
app.post("/api/orders/create", authenticateToken, async (req, res) => {
  const buyerId = req.userId;
  const { product_id, quantity, message } = req.body;

  if (!product_id || !quantity) {
    return res.status(400).json({ error: "Product ID and quantity are required." });
  }

  try {
    db.query(
      "SELECT * FROM products WHERE id = ?",
      [product_id],
      async (err, productResults) => {
        if (err) return res.status(500).json({ error: "Database error." });
        if (productResults.length === 0) {
          return res.status(404).json({ error: "Product not found." });
        }

        const product = productResults[0];

        if (!product.seller_id) {
          return res.status(400).json({ 
            error: "This product has no seller assigned." 
          });
        }

        const totalPrice = parseFloat(product.price) * parseInt(quantity);

        db.query(
          `SELECT id FROM conversations 
           WHERE (user1_id = ? AND user2_id = ?) 
           OR (user1_id = ? AND user2_id = ?)`,
          [buyerId, product.seller_id, product.seller_id, buyerId],
          (err, convResults) => {
            if (err) return res.status(500).json({ error: "Database error." });

            const createOrderAndNotify = (convId) => {
              const insertQuery = `
                INSERT INTO orders 
                (user_id, seller_id, product_id, product_name, quantity, price, 
                 status, seller_confirmed, seller_shipped, buyer_confirmed_receipt, 
                 dispute_raised, can_cancel_buyer, conversation_id) 
                VALUES (?, ?, ?, ?, ?, ?, 'Pending', 0, 0, 0, 0, 1, ?)
              `;
              
              db.query(
                insertQuery,
                [buyerId, product.seller_id, product_id, product.name, quantity, totalPrice, convId],
                (err, orderResult) => {
                  if (err) return res.status(500).json({ error: "Failed to create order." });

                  const orderId = orderResult.insertId;

                  // ✅ CREATE USER NOTIFICATION FOR SELLER
                  const notificationMessage = `New order for ${product.name} (Qty: ${quantity}) - Total: ₱${totalPrice.toFixed(2)}`;
                  
                  db.query(
                    `INSERT INTO user_notifications (user_id, title, message, type, reference_id, reference_type, is_read) 
                     VALUES (?, ?, ?, ?, ?, ?, 0)`,
                    [product.seller_id, 'New Order Received', notificationMessage, 'new_order', orderId, 'order'],
                    (err) => {
                      if (err) console.log('⚠️ Failed to create notification:', err);
                    }
                  );

                  // Send message
                  if (convId) {
                    const autoMessage = `🛒 New Order Request\n\nProduct: ${product.name}\nQuantity: ${quantity}\nTotal: ₱${totalPrice.toFixed(2)}\n\n${message || 'Please confirm this order.'}`;
                    
                    db.query(
                      "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
                      [convId, buyerId, autoMessage],
                      () => {}
                    );
                  }

                  res.status(201).json({
                    message: "Order placed successfully!",
                    order_id: orderId,
                    conversation_id: convId
                  });
                }
              );
            };

            if (convResults.length > 0) {
              createOrderAndNotify(convResults[0].id);
            } else {
              db.query(
                "INSERT INTO conversations (user1_id, user2_id) VALUES (?, ?)",
                [buyerId, product.seller_id],
                (err, newConvResult) => {
                  if (err) return res.status(500).json({ error: "Failed to create conversation." });
                  createOrderAndNotify(newConvResult.insertId);
                }
              );
            }
          }
        );
      }
    );
  } catch (e) {
    res.status(500).json({ error: "Server error." });
  }
});

// Export the createNotification function for use in other endpoints
export { createNotification };

// -------- SELLER MARKS ORDER AS SHIPPED --------
// -------- SELLER MARK AS SHIPPED (FIXED) --------
app.post("/api/orders/:orderId/mark-shipped", authenticateToken, (req, res) => {
  const sellerId = req.userId;
  const orderId = req.params.orderId;
  const { shipment_proof } = req.body;

  console.log('📦 Mark as shipped request:', orderId);

  db.query(
    `SELECT o.*, pay.status as payment_status
     FROM orders o
     LEFT JOIN payments pay ON o.id = pay.order_id
     WHERE o.id = ? AND o.seller_id = ?`,
    [orderId, sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];
      const isPaid = order.payment_status === 'paid' || order.payment_status === 'completed';

      console.log('  Current Status:', order.status);
      console.log('  Payment Status:', order.payment_status);
      console.log('  Is Paid:', isPaid);

      // ✅ CHECK IF BUYER HAS PAID
      if (!isPaid) {
        return res.status(400).json({ 
          error: "Cannot ship until buyer pays. Please wait for payment confirmation." 
        });
      }

      // ✅ FIX: Allow shipping for both Accepted AND Confirmed orders
      const allowedStatuses = ['Accepted', 'Confirmed'];
      if (!allowedStatuses.includes(order.status)) {
        return res.status(400).json({ 
          error: `Order must be accepted and paid first. Current status: ${order.status}` 
        });
      }

      // Check if already shipped
      if (order.seller_shipped === 1) {
        return res.status(400).json({ error: "Order already marked as shipped." });
      }

      // Update to Shipped
      db.query(
        "UPDATE orders SET seller_shipped = 1, status = 'Shipped', shipment_proof = ?, shipped_at = NOW() WHERE id = ?",
        [shipment_proof || null, orderId],
        (err) => {
          if (err) {
            console.error('❌ Failed to mark as shipped:', err);
            return res.status(500).json({ error: "Failed to mark as shipped." });
          }

          console.log('✅ Order marked as shipped');

          // Notify buyer
          createNotification(
            order.user_id,
            '📦 Order Shipped',
            `Your order for ${order.product_name} has been shipped! Please confirm receipt when you receive it.`,
            'order_shipped',
            orderId,
            'order'
          );

          // Send message
          if (order.conversation_id) {
            const shipMessage = `📦 Order Shipped\n\nYour order for ${order.product_name} has been shipped!\n\nPlease click "Complete Order" once you receive the item in good condition.${shipment_proof ? '\n\n📍 Tracking: ' + shipment_proof : ''}`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, sellerId, shipMessage],
              () => {}
            );
          }

          res.json({ message: "Order marked as shipped!" });
        }
      );
    }
  );
});
// -------- BUYER CONFIRMS RECEIPT & COMPLETES ORDER --------
app.post("/api/orders/:orderId/complete", authenticateToken, (req, res) => {
  const buyerId = req.userId;
  const orderId = req.params.orderId;
  const { rating, review } = req.body;

  db.query(
    "SELECT * FROM orders WHERE id = ? AND user_id = ?",
    [orderId, buyerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];

      if (!order.seller_shipped) {
        return res.status(400).json({ error: "Seller hasn't marked order as shipped yet." });
      }

      db.query(
        "UPDATE orders SET buyer_confirmed_receipt = 1, status = 'Completed', completion_date = NOW() WHERE id = ?",
        [orderId],
        (err) => {
          if (err) return res.status(500).json({ error: "Failed to complete order." });

          // Notify seller - money can be released
          createNotification(
            order.seller_id,
            '✅ Order Completed',
            `Order for ${order.product_name} has been completed by the buyer. Payment will be released.`,
            'order_completed',
            orderId,
            'order'
          );

          // Send message
          if (order.conversation_id) {
            const completeMessage = `✅ Order Completed\n\nBuyer has confirmed receipt of ${order.product_name}.\n\nThank you for your transaction!${review ? '\n\nReview: ' + review : ''}`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, buyerId, completeMessage],
              () => {}
            );
          }

          res.json({ message: "Order completed successfully! Thank you for your purchase." });
        }
      );
    }
  );
});

// -------- SELLER CANCELS ACCEPTED ORDER (Before shipping) --------
app.post("/api/orders/:orderId/seller-cancel-accepted", authenticateToken, (req, res) => {
  const sellerId = req.userId;
  const orderId = req.params.orderId;
  const { reason } = req.body;

  db.query(
    "SELECT * FROM orders WHERE id = ? AND seller_id = ?",
    [orderId, sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];

      if (order.seller_shipped) {
        return res.status(400).json({ error: "Cannot cancel after marking as shipped." });
      }

      db.query(
        "UPDATE orders SET status = 'Cancelled' WHERE id = ?",
        [orderId],
        (err) => {
          if (err) return res.status(500).json({ error: "Failed to cancel order." });

          // Return product to marketplace
          if (order.product_id) {
            db.query(
              "UPDATE products SET status = 'available' WHERE id = ?",
              [order.product_id],
              () => {}
            );
          }

          // Notify buyer - refund will be processed
          createNotification(
            order.user_id,
            'Order Cancelled by Seller',
            `Your order for ${order.product_name} has been cancelled by the seller. Your payment will be refunded.${reason ? ' Reason: ' + reason : ''}`,
            'order_cancelled',
            orderId,
            'order'
          );

          // Send message
          if (order.conversation_id) {
            const cancelMsg = `❌ Order Cancelled\n\nSeller has cancelled the order for ${order.product_name}.${reason ? '\n\nReason: ' + reason : ''}\n\n💰 Your payment will be refunded.\n📦 Product is now available again in the marketplace.`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, sellerId, cancelMsg],
              () => {}
            );
          }

          res.json({ message: "Order cancelled. Buyer will be refunded." });
        }
      );
    }
  );
});

// -------- RAISE DISPUTE (Buyer or Seller) --------
// -------- RAISE DISPUTE (FIXED - Replace your existing endpoint) --------
app.post("/api/orders/:orderId/dispute", authenticateToken, (req, res) => {
  const userId = req.userId;
  const orderId = req.params.orderId;
  const { reason } = req.body;

  console.log('⚠️ Dispute raised for order:', orderId, 'by user:', userId);

  if (!reason || reason.trim().length === 0) {
    return res.status(400).json({ error: "Dispute reason is required." });
  }

  db.query(
    "SELECT * FROM orders WHERE id = ? AND (user_id = ? OR seller_id = ?)",
    [orderId, userId, userId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];
      const isBuyer = order.user_id === userId;
      const raisedBy = isBuyer ? 'buyer' : 'seller'; // ✅ THIS IS THE KEY FIX

      console.log('👤 Dispute raised by:', raisedBy);

      // Check if already disputed
      if (order.dispute_raised === 1) {
        return res.status(400).json({ error: "Dispute already raised for this order." });
      }

      // ✅ UPDATE WITH dispute_raised_by
      db.query(
        "UPDATE orders SET dispute_raised = 1, dispute_reason = ?, dispute_raised_by = ?, status = 'Disputed', dispute_resolved = 0 WHERE id = ?",
        [reason, raisedBy, orderId],
        (err) => {
          if (err) {
            console.log('❌ Failed to raise dispute:', err);
            return res.status(500).json({ error: "Failed to raise dispute." });
          }

          console.log('✅ Dispute raised successfully by', raisedBy);

          // Notify admin
          db.query(
            "INSERT INTO notifications (title, message, type) VALUES (?, ?, ?)",
            [
              "⚠️ Order Dispute",
              `Order #${orderId} - ${order.product_name} disputed by ${isBuyer ? 'buyer' : 'seller'}. Reason: ${reason}`,
              "warning"
            ],
            () => {}
          );

          // Notify the other party
          const otherUserId = isBuyer ? order.seller_id : order.user_id;
          createNotification(
            otherUserId,
            'Order Dispute Raised',
            `A dispute has been raised by the ${raisedBy} for order: ${order.product_name}. Admin will review the case.`,
            'order_disputed',
            orderId,
            'order'
          );

          // Send message
          if (order.conversation_id) {
            const disputeMsg = `⚠️ Dispute Raised by ${raisedBy.toUpperCase()}\n\nReason: ${reason}\n\n🛡️ Admin will review and mediate. Please wait for further instructions.`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, userId, disputeMsg],
              () => {}
            );
          }

          res.json({ 
            message: "Dispute raised. Admin will review your case.",
            raised_by: raisedBy 
          });
        }
      );
    }
  );
});

app.get("/api/orders/by-conversation/:conversationId", authenticateToken, (req, res) => {
  const userId = req.userId;
  const conversationId = req.params.conversationId;

  db.query(
    `SELECT o.*, 
            p.name as product_name, 
            p.image_url as product_image,
            pay.status as payment_status,
            pay.escrow_status
     FROM orders o
     LEFT JOIN products p ON o.product_id = p.id
     LEFT JOIN payments pay ON o.id = pay.order_id
     WHERE o.conversation_id = ? 
     AND (o.user_id = ? OR o.seller_id = ?)
     ORDER BY o.created_at DESC
     LIMIT 1`,
    [conversationId, userId, userId],
    (err, results) => {
      if (err) {
        console.error('❌ Database error:', err);
        return res.status(500).json({ error: "Database error." });
      }
      
      // No order found OR order is completed/cancelled
      if (results.length === 0 || 
          (results[0].status === 'Completed' || results[0].status === 'Cancelled')) {
        return res.json({ has_active_order: false });
      }

      const order = results[0];
      const isBuyer = order.user_id === userId;
      const isSeller = order.seller_id === userId;

      console.log('\n📦 ===== ORDER STATUS CHECK =====');
      console.log('Order ID:', order.id);
      console.log('Product:', order.product_name);
      console.log('Status:', order.status);
      console.log('Payment Status:', order.payment_status || 'unpaid');
      console.log('User Type:', isBuyer ? 'BUYER' : 'SELLER');
      
      // 🔹 Convert to boolean (handle both 1 and true)
      const sellerConfirmed = !!(order.seller_confirmed === 1 || order.seller_confirmed === true);
      const sellerShipped = !!(order.seller_shipped === 1 || order.seller_shipped === true);
      const buyerConfirmed = !!(order.buyer_confirmed_receipt === 1 || order.buyer_confirmed_receipt === true);
      const disputeActive = !!(order.dispute_raised === 1 || order.dispute_raised === true);
      const isPaid = order.payment_status === 'paid' || order.payment_status === 'completed';

      console.log('Flags:');
      console.log('  Seller Confirmed:', sellerConfirmed);
      console.log('  Payment Received:', isPaid);
      console.log('  Seller Shipped:', sellerShipped);
      console.log('  Buyer Confirmed:', buyerConfirmed);
      console.log('  Dispute Active:', disputeActive);

      // ✅ CORRECT FLOW:
      // 1. Pending → Buyer places order
      // 2. Accepted → Seller accepts (buyer can pay or cancel)
      // 3. Confirmed → Buyer pays (seller can ship)
      // 4. Shipped → Seller ships (buyer can complete)
      // 5. Completed → Buyer confirms (payment released)

      // 🟦 BUYER PERMISSIONS
      const canPay = isBuyer && 
                     order.status === 'Accepted' && 
                     !isPaid;

      const canComplete = isBuyer && 
                         (sellerShipped || order.status === 'Shipped') && 
                         !buyerConfirmed &&
                         !disputeActive;

      const canBuyerCancel = isBuyer && 
                            order.status === 'Pending' && 
                            !sellerConfirmed;

      // 🟢 SELLER PERMISSIONS - ✅ THIS IS THE KEY FIX
      const canAccept = isSeller && 
                       order.status === 'Pending' && 
                       !sellerConfirmed;

      // ✅ FIX: Can ship if status is Confirmed (after payment) OR if already in Accepted state with payment
      const canShip = isSeller && 
                     (order.status === 'Confirmed' || (order.status === 'Accepted' && isPaid)) && 
                     !sellerShipped;

      const canSellerCancel = isSeller && 
                             (order.status === 'Pending' || order.status === 'Accepted' || order.status === 'Confirmed') && 
                             !sellerShipped;

      // ⚠️ BOTH can dispute (after payment)
      const canDispute = !disputeActive &&
                        (order.status === 'Accepted' || 
                         order.status === 'Confirmed' || 
                         order.status === 'Shipped');

      console.log('\n🎯 Calculated Permissions:');
      console.log('BUYER:');
      console.log('  ✓ Can Pay:', canPay);
      console.log('  ✓ Can Complete:', canComplete);
      console.log('  ✓ Can Cancel:', canBuyerCancel);
      console.log('SELLER:');
      console.log('  ✓ Can Accept:', canAccept);
      console.log('  ✓ Can Ship:', canShip, '← KEY FIX');
      console.log('  ✓ Can Cancel:', canSellerCancel);
      console.log('BOTH:');
      console.log('  ✓ Can Dispute:', canDispute);
      console.log('================================\n');

      res.json({
        has_active_order: true,
        order: {
          id: order.id,
          product_id: order.product_id,
          product_name: order.product_name,
          quantity: order.quantity,
          price: order.price,
          status: order.status,
          payment_status: order.payment_status || 'unpaid',
          seller_confirmed: sellerConfirmed,
          seller_shipped: sellerShipped,
          buyer_confirmed_receipt: buyerConfirmed,
          dispute_raised: disputeActive,
          created_at: order.created_at
        },
        is_buyer: isBuyer,
        is_seller: isSeller,
        can_accept: canAccept,
        can_pay: canPay,
        can_ship: canShip,  // ✅ Now correctly calculated
        can_cancel: canBuyerCancel || canSellerCancel,
        can_complete: canComplete,
        can_dispute: canDispute
      });
    }
  );
});

// Replace the GET /api/orders/by-conversation/:conversationId endpoint in server.js
// This should be around line 2400+ in your server.js

app.get("/api/orders/by-conversation/:conversationId", authenticateToken, (req, res) => {
  const userId = req.userId;
  const conversationId = req.params.conversationId;

  db.query(
    `SELECT o.*, 
            p.name as product_name, p.image_url as product_image
     FROM orders o
     LEFT JOIN products p ON o.product_id = p.id
     WHERE o.conversation_id = ? 
     AND (o.user_id = ? OR o.seller_id = ?)
     ORDER BY o.created_at DESC
     LIMIT 1`,
    [conversationId, userId, userId],
    (err, results) => {
      if (err) {
        console.log('❌ Error fetching order by conversation:', err);
        return res.status(500).json({ error: "Database error." });
      }
      
      // Check if order is already completed/cancelled - don't show it
      if (results.length === 0 || 
          (results[0].status === 'Completed' || results[0].status === 'Cancelled')) {
        return res.json({ has_active_order: false });
      }

      const order = results[0];
      const isBuyer = order.user_id === userId;
      const isSeller = order.seller_id === userId;

      console.log('📦 Order Status Check:');
      console.log('  Order ID:', order.id);
      console.log('  Product:', order.product_name);
      console.log('  Status:', order.status);
      console.log('  Is Buyer:', isBuyer);
      console.log('  Is Seller:', isSeller);
      console.log('  Seller Confirmed:', order.seller_confirmed);
      console.log('  Seller Shipped:', order.seller_shipped);
      console.log('  Buyer Confirmed Receipt:', order.buyer_confirmed_receipt);
      console.log('  Dispute Raised:', order.dispute_raised);

      // ✅ SELLER PERMISSIONS
      const canShip = isSeller && 
                     (order.status === 'Accepted' || order.status === 'Confirmed') && 
                     (order.seller_shipped !== 1 && order.seller_shipped !== true);

      const canCancel = isSeller && 
                       (order.status === 'Pending' || order.status === 'Accepted' || order.status === 'Confirmed') && 
                       (order.seller_shipped !== 1 && order.seller_shipped !== true);

      // ✅ BUYER PERMISSIONS
      const sellerHasShipped = (order.seller_shipped === 1 || order.seller_shipped === true) || order.status === 'Shipped';
      const buyerHasConfirmed = order.buyer_confirmed_receipt === 1 || order.buyer_confirmed_receipt === true;
      const disputeActive = order.dispute_raised === 1 || order.dispute_raised === true;
      
      const canComplete = isBuyer && 
                         sellerHasShipped && 
                         !buyerHasConfirmed &&
                         !disputeActive;

      // ✅ BOTH PARTIES CAN DISPUTE
      const canDispute = ((order.status === 'Accepted' || 
                         order.status === 'Confirmed' || 
                         order.status === 'Shipped') && 
                        !disputeActive);

      console.log('🔐 Calculated Permissions:');
      console.log('  Seller Has Shipped:', sellerHasShipped);
      console.log('  Buyer Has Confirmed:', buyerHasConfirmed);
      console.log('  Dispute Active:', disputeActive);
      console.log('  Can Ship:', canShip);
      console.log('  Can Cancel:', canCancel);
      console.log('  Can Complete:', canComplete);
      console.log('  Can Dispute:', canDispute);

      res.json({
        has_active_order: true,
        order: order,
        is_buyer: isBuyer,
        is_seller: isSeller,
        can_ship: canShip,
        can_cancel: canCancel,
        can_complete: canComplete,
        can_dispute: canDispute
      });
    }
  );
});

// Also update the mark-shipped endpoint to ensure proper status update
app.post("/api/orders/:orderId/mark-shipped", authenticateToken, (req, res) => {
  const sellerId = req.userId;
  const orderId = req.params.orderId;
  const { shipment_proof } = req.body;

  console.log('📦 Mark as shipped request:', orderId);

  db.query(
    "SELECT * FROM orders WHERE id = ? AND seller_id = ?",
    [orderId, sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];
      const isPaid = order.payment_status === 'paid' || order.payment_status === 'completed';

      console.log('  Current Status:', order.status);
      console.log('  Payment Status:', order.payment_status);
      console.log('  Is Paid:', isPaid);

      // ✅ CHECK IF BUYER HAS PAID
      if (!isPaid) {
        return res.status(400).json({ 
          error: "Cannot mark as shipped until buyer pays. Please wait for payment confirmation." 
        });
      }

      // Can only ship confirmed orders (after payment)
      if (order.status !== 'Confirmed') {
        return res.status(400).json({ error: "Order must be confirmed and paid first." });
      }

      // Check if already shipped
      if (order.seller_shipped === 1) {
        return res.status(400).json({ error: "Order already marked as shipped." });
      }

      // Update to Shipped
      db.query(
        "UPDATE orders SET seller_shipped = 1, status = 'Shipped', shipment_proof = ?, shipped_at = NOW() WHERE id = ?",
        [shipment_proof || null, orderId],
        (err) => {
          if (err) {
            console.log('❌ Failed to mark as shipped:', err);
            return res.status(500).json({ error: "Failed to mark as shipped." });
          }

          console.log('✅ Order marked as shipped');

          // Notify buyer
          createNotification(
            order.user_id,
            'Order Shipped',
            `Your order for ${order.product_name} has been shipped! Please confirm receipt when you receive it.`,
            'order_shipped',
            orderId,
            'order'
          );

          // Send message
          if (order.conversation_id) {
            const shipMessage = `📦 Order Shipped\n\nYour order for ${order.product_name} has been shipped!\n\nPlease click "Complete Order" once you receive the item in good condition.${shipment_proof ? '\n\nTracking: ' + shipment_proof : ''}`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, sellerId, shipMessage],
              () => {}
            );
          }

          res.json({ message: "Order marked as shipped!" });
        }
      );
    }
  );
});

// ✅ UPDATE PAYMENT PROCESSING TO CHANGE STATUS TO CONFIRMED
// Find your /api/payments/process endpoint and update the order status part:

// After creating payment successfully, add:

// ✅ UPDATE SELLER ACCEPT ORDER TO NOT CHANGE STATUS IF UNPAID
app.post("/api/orders/:orderId/accept", authenticateToken, (req, res) => {
  const sellerId = req.userId;
  const orderId = req.params.orderId;

  console.log('✅ Seller accepting order:', orderId);

  db.query(
    "SELECT * FROM orders WHERE id = ? AND seller_id = ?",
    [orderId, sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];

      if (order.status !== 'Pending') {
        return res.status(400).json({ error: "Order is not pending." });
      }

      // ✅ UPDATE TO ACCEPTED (NOT CONFIRMED YET - waiting for payment)
      db.query(
        "UPDATE orders SET status = 'Accepted', seller_confirmed = 1, can_cancel_buyer = 0 WHERE id = ?",
        [orderId],
        (err) => {
          if (err) return res.status(500).json({ error: "Failed to accept order." });

          console.log('✅ Order accepted - waiting for buyer payment');

          // Notify buyer to pay
          createNotification(
            order.user_id,
            'Order Accepted - Payment Required',
            `Your order for ${order.product_name} has been accepted! Please proceed with payment to confirm.`,
            'order_accepted',
            orderId,
            'order'
          );

          // Send message
          if (order.conversation_id) {
            const acceptMessage = `✅ Order Accepted\n\nYour order for ${order.product_name} (Qty: ${order.quantity}) has been accepted!\nTotal: ₱${order.price}\n\n💳 Please click "Pay Now" to complete your order.`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, sellerId, acceptMessage],
              () => {}
            );
          }

          res.json({ 
            message: "Order accepted! Waiting for buyer payment.",
            status: 'Accepted'
          });
        }
      );
    }
  );
});

app.get("/api/orders/by-conversation/:conversationId", authenticateToken, (req, res) => {
  const userId = req.userId;
  const conversationId = req.params.conversationId;

  db.query(
    `SELECT o.*, 
            p.name as product_name, 
            p.image_url as product_image
     FROM orders o
     LEFT JOIN products p ON o.product_id = p.id
     WHERE o.conversation_id = ? 
     AND (o.user_id = ? OR o.seller_id = ?)
     ORDER BY o.created_at DESC
     LIMIT 1`,
    [conversationId, userId, userId],
    (err, results) => {
      if (err) {
        return res.status(500).json({ error: "Database error." });
      }
      
      // No order found OR order is completed/cancelled
      if (results.length === 0 || 
          (results[0].status === 'Completed' || results[0].status === 'Cancelled')) {
        return res.json({ has_active_order: false });
      }

      const order = results[0];
      const isBuyer = order.user_id === userId;
      const isSeller = order.seller_id === userId;

      // ✅ CONVERT TO PROPER BOOLEANS
      const sellerConfirmed = !!(order.seller_confirmed === 1 || order.seller_confirmed === true);
      const sellerShipped = !!(order.seller_shipped === 1 || order.seller_shipped === true);
      const buyerConfirmed = !!(order.buyer_confirmed_receipt === 1 || order.buyer_confirmed_receipt === true);
      const disputeActive = !!(order.dispute_raised === 1 || order.dispute_raised === true);

      // ✅ CALCULATE PERMISSIONS
      
      // SELLER can ship after accepting (status = Accepted or Confirmed)
      const canShip = isSeller && 
                     (order.status === 'Accepted' || order.status === 'Confirmed') && 
                     !sellerShipped;

      // SELLER can cancel before shipping
      const canCancel = isSeller && 
                       (order.status === 'Pending' || order.status === 'Accepted' || order.status === 'Confirmed') && 
                       !sellerShipped;

      // BUYER can complete ONLY after seller marks as shipped
      const canComplete = isBuyer && 
                         (sellerShipped || order.status === 'Shipped') && 
                         !buyerConfirmed &&
                         !disputeActive;

      // BOTH can dispute after order is accepted/shipped
      const canDispute = !disputeActive &&
                        (order.status === 'Accepted' || 
                         order.status === 'Confirmed' || 
                         order.status === 'Shipped');

      // ✅ RETURN WITH EXPLICIT BOOLEAN VALUES
      res.json({
        has_active_order: true,
        order: {
          id: order.id,
          product_id: order.product_id,
          product_name: order.product_name,
          quantity: order.quantity,
          price: order.price,
          status: order.status,
          seller_confirmed: sellerConfirmed,
          seller_shipped: sellerShipped,
          buyer_confirmed_receipt: buyerConfirmed,
          dispute_raised: disputeActive,
          created_at: order.created_at
        },
        is_buyer: isBuyer,
        is_seller: isSeller,
        can_ship: canShip,
        can_cancel: canCancel,
        can_complete: canComplete,
        can_dispute: canDispute
      });
    }
  );
});

// ✅ CLEAN ORDER CREATION ENDPOINT
// Replace in server.js (around line 1125)

app.post("/api/orders/create", authenticateToken, async (req, res) => {
  const buyerId = req.userId;
  const { product_id, quantity, message } = req.body;

  if (!product_id || !quantity) {
    return res.status(400).json({ error: "Product ID and quantity are required." });
  }

  try {
    // Get product details
    db.query(
      "SELECT * FROM products WHERE id = ?",
      [product_id],
      async (err, productResults) => {
        if (err) return res.status(500).json({ error: "Database error." });
        if (productResults.length === 0) {
          return res.status(404).json({ error: "Product not found." });
        }

        const product = productResults[0];

        if (!product.seller_id) {
          return res.status(400).json({ 
            error: "This product has no seller assigned. Please contact admin." 
          });
        }

        const totalPrice = parseFloat(product.price) * parseInt(quantity);

        // Check or create conversation
        db.query(
          `SELECT id FROM conversations 
           WHERE (user1_id = ? AND user2_id = ?) 
           OR (user1_id = ? AND user2_id = ?)`,
          [buyerId, product.seller_id, product.seller_id, buyerId],
          (err, convResults) => {
            if (err) return res.status(500).json({ error: "Database error." });

            const createOrderAndNotify = (convId) => {
              // ✅ Create order with explicit status and flags
              const insertQuery = `
                INSERT INTO orders 
                (user_id, seller_id, product_id, product_name, quantity, price, 
                 status, seller_confirmed, seller_shipped, buyer_confirmed_receipt, 
                 dispute_raised, can_cancel_buyer, conversation_id) 
                VALUES (?, ?, ?, ?, ?, ?, 'Pending', 0, 0, 0, 0, 1, ?)
              `;
              
              db.query(
                insertQuery,
                [buyerId, product.seller_id, product_id, product.name, quantity, totalPrice, convId],
                (err, orderResult) => {
                  if (err) return res.status(500).json({ error: "Failed to create order." });

                  const orderId = orderResult.insertId;

                  // Create notification for seller
                  const notificationMessage = `New order for ${product.name} (Qty: ${quantity}) - Total: ₱${totalPrice.toFixed(2)}`;
                  
                  db.query(
                    `INSERT INTO user_notifications (user_id, title, message, type, reference_id, reference_type) 
                     VALUES (?, ?, ?, ?, ?, ?)`,
                    [product.seller_id, 'New Order Request', notificationMessage, 'new_order', orderId, 'order'],
                    () => {}
                  );

                  // Send automatic message
                  if (convId) {
                    const autoMessage = `🛒 New Order Request\n\nProduct: ${product.name}\nQuantity: ${quantity}\nTotal: ₱${totalPrice.toFixed(2)}\n\n${message || 'Please confirm this order.'}`;
                    
                    db.query(
                      "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
                      [convId, buyerId, autoMessage],
                      () => {}
                    );
                  }

                  res.status(201).json({
                    message: "Order placed successfully! Waiting for seller confirmation.",
                    order_id: orderId,
                    conversation_id: convId
                  });
                }
              );
            };

            if (convResults.length > 0) {
              createOrderAndNotify(convResults[0].id);
            } else {
              db.query(
                "INSERT INTO conversations (user1_id, user2_id) VALUES (?, ?)",
                [buyerId, product.seller_id],
                (err, newConvResult) => {
                  if (err) return res.status(500).json({ error: "Failed to create conversation." });
                  createOrderAndNotify(newConvResult.insertId);
                }
              );
            }
          }
        );
      }
    );
  } catch (e) {
    res.status(500).json({ error: "Server error." });
  }
});

// ✅ CLEAN SELLER ACCEPT ORDER
app.post("/api/orders/:orderId/accept", authenticateToken, (req, res) => {
  const sellerId = req.userId;
  const orderId = req.params.orderId;

  db.query(
    "SELECT * FROM orders WHERE id = ? AND seller_id = ?",
    [orderId, sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];

      if (order.status !== 'Pending') {
        return res.status(400).json({ error: "Order is not pending." });
      }

      // Update order to Accepted
      db.query(
        "UPDATE orders SET status = 'Accepted', seller_confirmed = 1, can_cancel_buyer = 0 WHERE id = ?",
        [orderId],
        (err) => {
          if (err) return res.status(500).json({ error: "Failed to accept order." });

          // Notify buyer
          db.query(
            `INSERT INTO user_notifications (user_id, title, message, type, reference_id, reference_type) 
             VALUES (?, ?, ?, ?, ?, ?)`,
            [order.user_id, 'Order Accepted', `Your order for ${order.product_name} has been accepted by the seller.`, 'order_accepted', orderId, 'order'],
            () => {}
          );

          // Send message
          if (order.conversation_id) {
            const acceptMessage = `✅ Order Accepted\n\nYour order for ${order.product_name} (Qty: ${order.quantity}) has been accepted!\nTotal: ₱${order.price}`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, sellerId, acceptMessage],
              () => {}
            );
          }

          res.json({ message: "Order accepted successfully!" });
        }
      );
    }
  );
});

app.post("/api/orders/:orderId/mark-shipped", authenticateToken, (req, res) => {
  const sellerId = req.userId;
  const orderId = req.params.orderId;
  const { shipment_proof } = req.body;

  console.log('📦 Mark as shipped request:', orderId);

  db.query(
    `SELECT o.*, pay.status as payment_status
     FROM orders o
     LEFT JOIN payments pay ON o.id = pay.order_id
     WHERE o.id = ? AND o.seller_id = ?`,
    [orderId, sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];
      const isPaid = order.payment_status === 'paid' || order.payment_status === 'completed';

      console.log('  Status:', order.status);
      console.log('  Payment Status:', order.payment_status);
      console.log('  Is Paid:', isPaid);

      // ✅ CHECK IF BUYER HAS PAID
      if (!isPaid) {
        return res.status(400).json({ 
          error: "Cannot ship until buyer pays. Please wait for payment confirmation." 
        });
      }

      // Can only ship confirmed orders (after payment)
      if (order.status !== 'Confirmed') {
        return res.status(400).json({ 
          error: "Order must be confirmed with payment first." 
        });
      }

      // Check if already shipped
      if (order.seller_shipped === 1) {
        return res.status(400).json({ error: "Order already marked as shipped." });
      }

      // Update to Shipped
      db.query(
        "UPDATE orders SET seller_shipped = 1, status = 'Shipped', shipment_proof = ?, shipped_at = NOW() WHERE id = ?",
        [shipment_proof || null, orderId],
        (err) => {
          if (err) {
            console.error('❌ Failed to mark as shipped:', err);
            return res.status(500).json({ error: "Failed to mark as shipped." });
          }

          console.log('✅ Order marked as shipped');

          // Notify buyer
          createNotification(
            order.user_id,
            '📦 Order Shipped',
            `Your order for ${order.product_name} has been shipped! Please confirm receipt when you receive it.`,
            'order_shipped',
            orderId,
            'order'
          );

          // Send message
          if (order.conversation_id) {
            const shipMessage = `📦 Order Shipped\n\nYour order for ${order.product_name} has been shipped!\n\nPlease click "Complete Order" once you receive the item in good condition.${shipment_proof ? '\n\n📍 Tracking: ' + shipment_proof : ''}`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, sellerId, shipMessage],
              () => {}
            );
          }

          res.json({ message: "Order marked as shipped!" });
        }
      );
    }
  );
});

app.post("/api/orders/:orderId/accept", authenticateToken, (req, res) => {
  const sellerId = req.userId;
  const orderId = req.params.orderId;

  console.log('✅ Accept order request:', orderId, 'by seller:', sellerId);

  db.query(
    "SELECT * FROM orders WHERE id = ? AND seller_id = ?",
    [orderId, sellerId],
    (err, results) => {
      if (err) {
        console.log('❌ Database error:', err);
        return res.status(500).json({ error: "Database error." });
      }
      if (results.length === 0) {
        console.log('❌ Order not found or unauthorized');
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];
      console.log('📦 Current order status:', order.status);

      if (order.status !== 'Pending') {
        console.log('❌ Order is not pending');
        return res.status(400).json({ error: "Order is not pending." });
      }

      // ✅ Update order to Accepted with explicit values
      db.query(
        "UPDATE orders SET status = 'Accepted', seller_confirmed = 1, can_cancel_buyer = 0 WHERE id = ?",
        [orderId],
        (err) => {
          if (err) {
            console.log('❌ Failed to accept order:', err);
            return res.status(500).json({ error: "Failed to accept order." });
          }

          console.log('✅ Order accepted successfully');

          // Verify update
          db.query(
            "SELECT status, seller_confirmed FROM orders WHERE id = ?",
            [orderId],
            (err, verifyResults) => {
              if (err || verifyResults.length === 0) {
                console.log('❌ Verification failed');
              } else {
                console.log('✅ Verified:', verifyResults[0]);
              }
            }
          );

          // Notify buyer
          db.query(
            `INSERT INTO user_notifications (user_id, title, message, type, reference_id, reference_type) 
             VALUES (?, ?, ?, ?, ?, ?)`,
            [order.user_id, 'Order Accepted', `Your order for ${order.product_name} has been accepted by the seller.`, 'order_accepted', orderId, 'order'],
            () => {}
          );

          // Send message
          if (order.conversation_id) {
            const acceptMessage = `✅ Order Accepted\n\nYour order for ${order.product_name} (Qty: ${order.quantity}) has been accepted!\nTotal: ₱${order.price}`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, sellerId, acceptMessage],
              () => {}
            );
          }

          res.json({ message: "Order accepted successfully!" });
        }
      );
    }
  );
});

// -------- SELLER MARK AS SHIPPED (FIXED) --------
app.post("/api/orders/:orderId/mark-shipped", authenticateToken, (req, res) => {
  const sellerId = req.userId;
  const orderId = req.params.orderId;
  const { shipment_proof } = req.body;

  console.log('📦 Mark as shipped request:', orderId);

  db.query(
    "SELECT * FROM orders WHERE id = ? AND seller_id = ?",
    [orderId, sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];

      console.log('  Current Status:', order.status);

      // Can only ship accepted/confirmed orders
      if (order.status !== 'Accepted' && order.status !== 'Confirmed') {
        return res.status(400).json({ error: "Order must be accepted first." });
      }

      // Check if already shipped
      if (order.seller_shipped === 1) {
        return res.status(400).json({ error: "Order already marked as shipped." });
      }

      // Update to Shipped
      db.query(
        "UPDATE orders SET seller_shipped = 1, status = 'Shipped', shipment_proof = ?, shipped_at = NOW() WHERE id = ?",
        [shipment_proof || null, orderId],
        (err) => {
          if (err) {
            console.log('❌ Failed to mark as shipped:', err);
            return res.status(500).json({ error: "Failed to mark as shipped." });
          }

          console.log('✅ Order marked as shipped');

          // Notify buyer
          createNotification(
            order.user_id,
            'Order Shipped',
            `Your order for ${order.product_name} has been shipped! Please confirm receipt when you receive it.`,
            'order_shipped',
            orderId,
            'order'
          );

          // Send message
          if (order.conversation_id) {
            const shipMessage = `📦 Order Shipped\n\nYour order for ${order.product_name} has been shipped!\n\nPlease click "Complete Order" once you receive the item in good condition.${shipment_proof ? '\n\nTracking: ' + shipment_proof : ''}`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, sellerId, shipMessage],
              () => {}
            );
          }

          res.json({ message: "Order marked as shipped!" });
        }
      );
    }
  );
});

// -------- BUYER COMPLETE ORDER (FIXED) --------
// 🔍 DIAGNOSTIC VERSION - Replace /api/orders/by-conversation/:conversationId

// 🔍 DIAGNOSTIC VERSION - Replace /api/orders/by-conversation/:conversationId

app.get("/api/orders/by-conversation/:conversationId", authenticateToken, (req, res) => {
  const userId = req.userId;
  const conversationId = req.params.conversationId;

  db.query(
    `SELECT o.*, p.name as product_name, p.image_url as product_image
     FROM orders o
     LEFT JOIN products p ON o.product_id = p.id
     WHERE o.conversation_id = ? 
     AND (o.user_id = ? OR o.seller_id = ?)
     ORDER BY o.created_at DESC
     LIMIT 1`,
    [conversationId, userId, userId],
    (err, results) => {
      if (err) {
        console.log('❌ Database error:', err);
        return res.status(500).json({ error: "Database error." });
      }
      
      if (results.length === 0) {
        console.log('ℹ️ No orders found for conversation:', conversationId);
        return res.json({ has_active_order: false });
      }

      const order = results[0];

      // 🔍 FULL DIAGNOSTIC DUMP
      console.log('🔍 ==== FULL ORDER DATA ====');
      console.log('Raw Order Object:', JSON.stringify(order, null, 2));
      console.log('');
      console.log('📋 Key Fields:');
      console.log('  id:', order.id);
      console.log('  status:', order.status, '(type:', typeof order.status, ')');
      console.log('  user_id:', order.user_id);
      console.log('  seller_id:', order.seller_id);
      console.log('  seller_confirmed:', order.seller_confirmed, '(type:', typeof order.seller_confirmed, ')');
      console.log('  seller_shipped:', order.seller_shipped, '(type:', typeof order.seller_shipped, ')');
      console.log('  buyer_confirmed_receipt:', order.buyer_confirmed_receipt, '(type:', typeof order.buyer_confirmed_receipt, ')');
      console.log('  dispute_raised:', order.dispute_raised, '(type:', typeof order.dispute_raised, ')');
      console.log('');

      // Hide completed/cancelled
      if (order.status === 'Completed' || order.status === 'Cancelled') {
        console.log('ℹ️ Order is completed/cancelled');
        return res.json({ has_active_order: false });
      }

      const isBuyer = order.user_id === userId;
      const isSeller = order.seller_id === userId;
      
      // Get status (try multiple ways)
      let status = '';
      if (order.status) {
        status = order.status.toString().trim();
      }
      
      console.log('👤 User Check:');
      console.log('  Current User ID:', userId);
      console.log('  Is Buyer:', isBuyer);
      console.log('  Is Seller:', isSeller);
      console.log('  Final Status String:', `"${status}"`);
      console.log('');

      // Convert to boolean (multiple possible values)
      const shipped = order.seller_shipped === 1 || order.seller_shipped === '1' || order.seller_shipped === true;
      const confirmed = order.buyer_confirmed_receipt === 1 || order.buyer_confirmed_receipt === '1' || order.buyer_confirmed_receipt === true;
      const disputed = order.dispute_raised === 1 || order.dispute_raised === '1' || order.dispute_raised === true;
      const sellerConfirmed = order.seller_confirmed === 1 || order.seller_confirmed === '1' || order.seller_confirmed === true;

      console.log('✅ Boolean Conversions:');
      console.log('  seller_confirmed:', sellerConfirmed);
      console.log('  shipped:', shipped);
      console.log('  confirmed:', confirmed);
      console.log('  disputed:', disputed);
      console.log('');

      // ✅ CALCULATE PERMISSIONS (with ALL possible status values)
      const isPending = status === 'Pending' || status === 'pending';
      const isAccepted = status === 'Accepted' || status === 'accepted' || status === 'Confirmed' || status === 'confirmed';
      const isShipped = status === 'Shipped' || status === 'shipped';

      const canShip = isSeller && isAccepted && !shipped;
      const canCancel = isSeller && (isPending || isAccepted) && !shipped;
      const canComplete = isBuyer && (shipped || isShipped) && !confirmed && !disputed;
      const canDispute = !disputed && (isAccepted || isShipped);

      console.log('🎯 Status Checks:');
      console.log('  isPending:', isPending);
      console.log('  isAccepted:', isAccepted);
      console.log('  isShipped:', isShipped);
      console.log('');
      console.log('🎯 Final Permissions:');
      console.log('  canShip:', canShip, '(seller:', isSeller, 'accepted:', isAccepted, 'not_shipped:', !shipped, ')');
      console.log('  canCancel:', canCancel);
      console.log('  canComplete:', canComplete);
      console.log('  canDispute:', canDispute);
      console.log('============================\n');

      res.json({
        has_active_order: true,
        order: order,
        is_buyer: isBuyer,
        is_seller: isSeller,
        can_ship: canShip,
        can_cancel: canCancel,
        can_complete: canComplete,
        can_dispute: canDispute
      });
    }
  );
});

// -------- SELLER CANCEL ORDER (FIXED) --------
app.post("/api/orders/:orderId/seller-cancel-accepted", authenticateToken, (req, res) => {
  const sellerId = req.userId;
  const orderId = req.params.orderId;
  const { reason } = req.body;

  console.log('❌ Cancel order request:', orderId, 'by seller:', sellerId);

  db.query(
    "SELECT * FROM orders WHERE id = ? AND seller_id = ?",
    [orderId, sellerId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];

      // Can't cancel after shipping
      if (order.seller_shipped === 1) {
        return res.status(400).json({ error: "Cannot cancel after marking as shipped." });
      }

      // Cancel order
      db.query(
        "UPDATE orders SET status = 'Cancelled' WHERE id = ?",
        [orderId],
        (err) => {
          if (err) {
            console.log('❌ Failed to cancel order:', err);
            return res.status(500).json({ error: "Failed to cancel order." });
          }

          console.log('✅ Order cancelled');

          // Return product to marketplace
          if (order.product_id) {
            db.query(
              "UPDATE products SET status = 'available' WHERE id = ?",
              [order.product_id],
              () => {}
            );
          }

          // Notify buyer
          createNotification(
            order.user_id,
            'Order Cancelled by Seller',
            `Your order for ${order.product_name} has been cancelled by the seller.${reason ? ' Reason: ' + reason : ''}`,
            'order_cancelled',
            orderId,
            'order'
          );

          // Send message
          if (order.conversation_id) {
            const cancelMsg = `❌ Order Cancelled\n\nSeller cancelled the order for ${order.product_name}.${reason ? '\n\nReason: ' + reason : ''}\n\n💰 Your payment will be refunded.\n📦 Product is now available in marketplace.`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, sellerId, cancelMsg],
              () => {}
            );
          }

          res.json({ message: "Order cancelled successfully." });
        }
      );
    }
  );
});

// -------- RAISE DISPUTE (FIXED) --------
app.post("/api/orders/:orderId/dispute", authenticateToken, (req, res) => {
  const userId = req.userId;
  const orderId = req.params.orderId;
  const { reason } = req.body;

  console.log('⚠️ Dispute raised for order:', orderId, 'by user:', userId);

  if (!reason || reason.trim().length === 0) {
    return res.status(400).json({ error: "Dispute reason is required." });
  }

  db.query(
    "SELECT * FROM orders WHERE id = ? AND (user_id = ? OR seller_id = ?)",
    [orderId, userId, userId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];
      const isBuyer = order.user_id === userId;

      // Check if already disputed
      if (order.dispute_raised === 1) {
        return res.status(400).json({ error: "Dispute already raised for this order." });
      }

      // Update order
      db.query(
        "UPDATE orders SET dispute_raised = 1, dispute_reason = ?, status = 'Disputed' WHERE id = ?",
        [reason, orderId],
        (err) => {
          if (err) {
            console.log('❌ Failed to raise dispute:', err);
            return res.status(500).json({ error: "Failed to raise dispute." });
          }

          console.log('✅ Dispute raised successfully');

          // Notify admin
          db.query(
            "INSERT INTO notifications (title, message, type) VALUES (?, ?, ?)",
            [
              "⚠️ Order Dispute",
              `Order #${orderId} - ${order.product_name} disputed by ${isBuyer ? 'buyer' : 'seller'}. Reason: ${reason}`,
              "warning"
            ],
            () => {}
          );

          // Notify other party
          const otherUserId = isBuyer ? order.seller_id : order.user_id;
          createNotification(
            otherUserId,
            'Order Dispute Raised',
            `A dispute has been raised for order: ${order.product_name}. Admin will review the case.`,
            'order_disputed',
            orderId,
            'order'
          );

          // Send message
          if (order.conversation_id) {
            const disputeMsg = `⚠️ Dispute Raised\n\nA dispute has been raised for this order.\n\nReason: ${reason}\n\n🛡️ Admin will review and mediate. Please wait for further instructions.`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, userId, disputeMsg],
              () => {}
            );
          }

          res.json({ message: "Dispute raised. Admin will review your case." });
        }
      );
    }
  );
});

app.get("/api/blockchain/transactions", authenticateToken, (req, res) => {
  db.query(
    `SELECT 
      'order' as type,
      o.id as transaction_id,
      o.product_name as product,
      u.username as buyer,
      s.username as seller,
      o.price,
      o.quantity,
      o.status,
      o.created_at as timestamp
     FROM orders o
     LEFT JOIN users u ON o.user_id = u.id
     LEFT JOIN users s ON o.seller_id = s.id
     ORDER BY o.created_at DESC
     LIMIT 100`,
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      res.json({ transactions: results });
    }
  );
});

// ✅ SIMPLE BLOCKCHAIN - Add this to your server.js

// -------- GET BLOCKCHAIN TRANSACTIONS (SIMPLE) --------
app.get("/api/blockchain/transactions", authenticateToken, (req, res) => {
  const query = `
    SELECT 
      o.id as transaction_id,
      o.product_name as product,
      buyer.username as buyer,
      seller.username as seller,
      o.price,
      o.quantity,
      o.status,
      o.created_at as timestamp
    FROM orders o
    LEFT JOIN users buyer ON o.user_id = buyer.id
    LEFT JOIN users seller ON o.seller_id = seller.id
    WHERE o.status = 'Completed'
    ORDER BY o.created_at DESC
    LIMIT 100
  `;

  db.query(query, (err, results) => {
    if (err) {
      console.error('❌ Blockchain query error:', err);
      return res.status(500).json({ error: "Database error." });
    }
    
    console.log('✅ Blockchain transactions loaded:', results.length);
    res.json({ transactions: results });
  });
});

// -------- GET MESSAGES FOR ADMIN (ANY CONVERSATION) --------
app.get("/api/admin/messages/:conversationId", isAdmin, (req, res) => {
  const conversationId = req.params.conversationId;

  // Get messages with media info - NO USER ACCESS CHECK FOR ADMIN
  const query = `
    SELECT 
      m.*,
      u.username as sender_name,
      u.role as sender_role
    FROM messages m
    LEFT JOIN users u ON m.sender_id = u.id
    WHERE m.conversation_id = ?
    ORDER BY m.created_at ASC
  `;

  db.query(query, [conversationId], (err, results) => {
    if (err) return res.status(500).json({ error: "Database error." });
    res.json({ messages: results });
  });
});

// ============================================
// ADMIN DISPUTE MANAGEMENT ROUTES
// ============================================

// -------- GET ALL DISPUTES (ADMIN) --------
// -------- GET ALL DISPUTES (ADMIN) --------
app.get("/api/admin/disputes", isAdmin, (req, res) => {
  const query = `
    SELECT 
      o.id,
      o.id as order_id,
      o.product_name,
      o.price as order_amount,
      o.dispute_reason as reason,
      COALESCE(o.dispute_raised_by, 
        CASE 
          WHEN o.dispute_raised = 1 THEN 'unknown'
          ELSE NULL 
        END) as dispute_raised_by,
      o.dispute_resolved,
      o.dispute_winner as winner,
      o.dispute_resolution as resolution,
      o.created_at,
      o.status,
      buyer.username as buyer_name,
      buyer.email as buyer_email,
      seller.username as seller_name,
      seller.email as seller_email,
      CASE 
        WHEN o.dispute_resolved = 1 THEN 'resolved'
        ELSE 'pending'
      END as status
    FROM orders o
    LEFT JOIN users buyer ON o.user_id = buyer.id
    LEFT JOIN users seller ON o.seller_id = seller.id
    WHERE o.dispute_raised = 1
    ORDER BY 
      CASE WHEN o.dispute_resolved = 0 THEN 0 ELSE 1 END,
      o.created_at DESC
  `;

  db.query(query, (err, results) => {
    if (err) {
      console.error('❌ Error fetching disputes:', err);
      return res.status(500).json({ error: "Database error." });
    }
    
    console.log(`✅ Loaded ${results.length} disputes`);
    res.json({ disputes: results });
  });
});

// -------- RAISE DISPUTE (Buyer or Seller) --------
app.post("/api/orders/:orderId/dispute", authenticateToken, (req, res) => {
  const userId = req.userId;
  const orderId = req.params.orderId;
  const { reason } = req.body;

  if (!reason || reason.trim().length === 0) {
    return res.status(400).json({ error: "Dispute reason is required." });
  }

  db.query(
    "SELECT * FROM orders WHERE id = ? AND (user_id = ? OR seller_id = ?)",
    [orderId, userId, userId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Order not found or unauthorized." });
      }

      const order = results[0];
      const isBuyer = order.user_id === userId;
      const raisedBy = isBuyer ? 'buyer' : 'seller';

      // Check if already disputed
      if (order.dispute_raised === 1) {
        return res.status(400).json({ error: "Dispute already raised for this order." });
      }

      // Update order with dispute information including who raised it
      db.query(
        "UPDATE orders SET dispute_raised = 1, dispute_reason = ?, dispute_raised_by = ?, status = 'Disputed', dispute_resolved = 0 WHERE id = ?",
        [reason, raisedBy, orderId],
        (err) => {
          if (err) {
            console.log('❌ Failed to raise dispute:', err);
            return res.status(500).json({ error: "Failed to raise dispute." });
          }

          console.log(`✅ Dispute raised by ${raisedBy}`);

          // Notify admin
          db.query(
            "INSERT INTO notifications (title, message, type) VALUES (?, ?, ?)",
            [
              "⚠️ Order Dispute",
              `Order #${orderId} - ${order.product_name} disputed by ${isBuyer ? 'buyer' : 'seller'}. Reason: ${reason}`,
              "warning"
            ],
            () => {}
          );

          // Notify other party
          const otherUserId = isBuyer ? order.seller_id : order.user_id;
          createNotification(
            otherUserId,
            'Order Dispute Raised',
            `A dispute has been raised by the ${raisedBy} for order: ${order.product_name}. Admin will review the case.`,
            'order_disputed',
            orderId,
            'order'
          );

          // Send message
          if (order.conversation_id) {
            const disputeMsg = `⚠️ Dispute Raised by ${raisedBy.toUpperCase()}\n\nReason: ${reason}\n\n🛡️ Admin will review and mediate. Please wait for further instructions.`;
            
            db.query(
              "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
              [order.conversation_id, userId, disputeMsg],
              () => {}
            );
          }

          res.json({ 
            message: "Dispute raised. Admin will review your case.",
            raised_by: raisedBy 
          });
        }
      );
    }
  );
});



app.post("/api/admin/disputes/:orderId/resolve", isAdmin, (req, res) => {
  const orderId = req.params.orderId;
  const { resolution, winner } = req.body;

  console.log('🔍 ===== RESOLVE DISPUTE SERVER =====');
  console.log('Order ID from params:', orderId);
  console.log('Resolution:', resolution);
  console.log('Winner:', winner);

  if (!resolution || !winner) {
    return res.status(400).json({ error: "Resolution and winner are required." });
  }

  if (!['buyer', 'seller'].includes(winner)) {
    return res.status(400).json({ error: "Winner must be 'buyer' or 'seller'." });
  }

  console.log(`⚖️ Resolving dispute for order #${orderId} in favor of ${winner}`);

  // Get order details first
  db.query(
    "SELECT * FROM orders WHERE id = ? AND dispute_raised = 1",
    [orderId],
    (err, orderResults) => {
      if (err) {
        console.error('❌ Database error:', err);
        return res.status(500).json({ error: "Database error." });
      }
      if (orderResults.length === 0) {
        return res.status(404).json({ error: "Dispute not found." });
      }

      const order = orderResults[0];

      // ✅ FIXED: Remove updated_at column reference
      db.query(
        `UPDATE orders 
         SET dispute_resolved = 1,
             dispute_winner = ?,
             dispute_resolution = ?,
             status = 'Completed'
         WHERE id = ?`,
        [winner, resolution, orderId],
        (err, result) => {
          if (err) {
            console.error('❌ Failed to resolve dispute:', err);
            return res.status(500).json({ error: "Failed to resolve dispute." });
          }

          console.log('✅ Dispute resolved successfully');

          // Handle payment based on winner
          handlePaymentResolution(orderId, winner, resolution, order, res);
        }
      );
    }
  );
});

// Helper function to handle payment resolution
// Helper function to handle payment resolution
function handlePaymentResolution(orderId, winner, resolution, order, res) {
  // Check if payment exists
  db.query(
    "SELECT * FROM payments WHERE order_id = ?",
    [orderId],
    (err, paymentResults) => {
      if (err) {
        console.error('❌ Error checking payment:', err);
      }
      
      if (paymentResults.length > 0) {
        // Update payment if exists
        const updateQuery = winner === 'buyer' 
          ? `UPDATE payments SET escrow_status = 'refunded', refund_reason = ? WHERE order_id = ?`
          : `UPDATE payments SET escrow_status = 'released' WHERE order_id = ?`;
        
        const values = winner === 'buyer' 
          ? [`Admin decision: ${resolution}`, orderId]
          : [orderId];
        
        db.query(updateQuery, values, (err) => {
          if (err) console.error('❌ Payment update error:', err);
        });
      } else {
        console.log('ℹ️ No payment record found for order #', orderId);
      }
      
      // Send notifications
      sendResolutionNotifications(orderId, winner, resolution, order, res);
    }
  );
}

function sendResolutionNotifications(orderId, winner, resolution, order, res) {
  // Notify both parties
  const buyerMsg = winner === 'buyer' 
    ? `Your dispute has been resolved in your favor. Refund of ₱${order.price} will be processed.`
    : `Dispute resolved in seller's favor. Payment has been released to seller.`;
  
  const sellerMsg = winner === 'seller'
    ? `Your dispute has been resolved in your favor. Payment of ₱${order.price} has been released.`
    : `Dispute resolved in buyer's favor. Payment will be refunded to buyer.`;

  // Notify buyer
  createNotification(
    order.user_id,
    winner === 'buyer' ? '✅ Dispute Resolved - Refund Issued' : '⚖️ Dispute Resolved',
    buyerMsg,
    'dispute_resolved',
    orderId,
    'order'
  );

  // Notify seller
  createNotification(
    order.seller_id,
    winner === 'seller' ? '✅ Dispute Resolved - Payment Released' : '⚖️ Dispute Resolved',
    sellerMsg,
    'dispute_resolved',
    orderId,
    'order'
  );

  // Send message to conversation
  if (order.conversation_id) {
    const resolutionMsg = `⚖️ Dispute Resolved by Admin\n\nDecision: ${winner.toUpperCase()} WINS\n\nReason: ${resolution}\n\n${winner === 'buyer' ? '💰 Refund will be processed to buyer.' : '💰 Payment released to seller.'}`;
    
    db.query(
      "INSERT INTO messages (conversation_id, sender_id, message) VALUES (?, ?, ?)",
      [order.conversation_id, 0, resolutionMsg], // 0 or admin ID
      () => {}
    );
  }

  res.json({
    success: true,
    message: "Dispute resolved successfully.",
    winner: winner,
    resolution: resolution
  });
}

app.get("/api/profile", authenticateToken, (req, res) => {
  const userId = req.userId;

  db.query(
    `SELECT id, username, email, phone, address, bio, profile_image, 
            role, is_approved, two_factor_enabled, created_at 
     FROM users WHERE id = ?`,
    [userId],
    (err, results) => {
      if (err) {
        console.error('Profile fetch error:', err);
        return res.status(500).json({ error: "Database error." });
      }
      if (results.length === 0) {
        return res.status(404).json({ error: "User not found." });
      }
      res.json({ profile: results[0] });
    }
  );
});

// -------- UPDATE USER PROFILE --------
app.put("/api/profile", upload.single('profile_image'), authenticateToken, (req, res) => {
  const userId = req.userId;
  const { username, email, phone, address, bio } = req.body;
  let profileImage = req.body.profile_image;

  if (req.file) {
    profileImage = `/uploads/${req.file.filename}`;
  }

  let updateFields = [];
  let updateValues = [];

  if (username) {
    updateFields.push("username = ?");
    updateValues.push(username);
  }
  if (email) {
    updateFields.push("email = ?");
    updateValues.push(email);
  }
  if (phone !== undefined) {
    updateFields.push("phone = ?");
    updateValues.push(phone);
  }
  if (address !== undefined) {
    updateFields.push("address = ?");
    updateValues.push(address);
  }
  if (bio !== undefined) {
    updateFields.push("bio = ?");
    updateValues.push(bio);
  }
  if (profileImage) {
    updateFields.push("profile_image = ?");
    updateValues.push(profileImage);
  }

  if (updateFields.length === 0) {
    return res.status(400).json({ error: "No fields to update." });
  }

  updateValues.push(userId);

  db.query(
    `UPDATE users SET ${updateFields.join(", ")} WHERE id = ?`,
    updateValues,
    (err) => {
      if (err) {
        if (err.code === 'ER_DUP_ENTRY') {
          return res.status(400).json({ error: "Email already exists." });
        }
        console.error('Profile update error:', err);
        return res.status(500).json({ error: "Failed to update profile." });
      }

      // Log activity
      logActivity(userId, 'profile_update', 'Profile information updated');

      res.json({ message: "Profile updated successfully!" });
    }
  );
});

// ============================================
// LOGIN HISTORY ENDPOINTS
// ============================================

// -------- RECORD LOGIN (Call this in your login endpoint) --------
function recordLogin(userId, success, ipAddress, device) {
  db.query(
    `INSERT INTO login_history (user_id, success, ip_address, device) 
     VALUES (?, ?, ?, ?)`,
    [userId, success ? 1 : 0, ipAddress, device],
    (err) => {
      if (err) console.error('Login history error:', err);
    }
  );
}

// -------- GET LOGIN HISTORY --------
app.get("/api/auth/login-history", authenticateToken, (req, res) => {
  const userId = req.userId;
  const limit = req.query.limit || 50;

  db.query(
    `SELECT id, success, ip_address, device, created_at 
     FROM login_history 
     WHERE user_id = ? 
     ORDER BY created_at DESC 
     LIMIT ?`,
    [userId, parseInt(limit)],
    (err, results) => {
      if (err) {
        console.error('Login history fetch error:', err);
        return res.status(500).json({ error: "Database error." });
      }
      res.json({ login_history: results });
    }
  );
});

// ============================================
// ACTIVITY LOGS ENDPOINTS
// ============================================

// -------- LOG ACTIVITY (Helper function) --------
function logActivity(userId, actionType, description, metadata = null) {
  db.query(
    `INSERT INTO activity_logs (user_id, action_type, description, metadata) 
     VALUES (?, ?, ?, ?)`,
    [userId, actionType, description, metadata ? JSON.stringify(metadata) : null],
    (err) => {
      if (err) console.error('Activity log error:', err);
    }
  );
}

// -------- GET ACTIVITY LOGS --------
app.get("/api/activity-logs", authenticateToken, (req, res) => {
  const userId = req.userId;
  const limit = req.query.limit || 50;

  db.query(
    `SELECT id, action_type, description, metadata, created_at 
     FROM activity_logs 
     WHERE user_id = ? 
     ORDER BY created_at DESC 
     LIMIT ?`,
    [userId, parseInt(limit)],
    (err, results) => {
      if (err) {
        console.error('Activity logs fetch error:', err);
        return res.status(500).json({ error: "Database error." });
      }
      res.json({ logs: results });
    }
  );
});

// ============================================
// TWO-FACTOR AUTHENTICATION ENDPOINTS
// ============================================

// -------- SETUP 2FA --------
app.post("/api/auth/setup-2fa", authenticateToken, (req, res) => {
  const userId = req.userId;

  // Check if 2FA is already enabled
  db.query(
    "SELECT two_factor_enabled, username, email FROM users WHERE id = ?",
    [userId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) return res.status(404).json({ error: "User not found." });

      const user = results[0];

      if (user.two_factor_enabled) {
        return res.status(400).json({ error: "2FA is already enabled." });
      }

      // Generate secret
      const secret = speakeasy.generateSecret({
        name: `AgriMarket (${user.email})`,
        length: 32
      });

      // Generate QR code
      QRCode.toDataURL(secret.otpauth_url, (err, qrCodeUrl) => {
        if (err) {
          console.error('QR code generation error:', err);
          return res.status(500).json({ error: "Failed to generate QR code." });
        }

        // Store temporary secret (not yet enabled)
        db.query(
          "UPDATE users SET two_factor_secret = ? WHERE id = ?",
          [secret.base32, userId],
          (err) => {
            if (err) {
              console.error('2FA setup error:', err);
              return res.status(500).json({ error: "Failed to setup 2FA." });
            }

            res.json({
              qr_code: qrCodeUrl,
              secret: secret.base32,
              message: "Scan QR code with Google Authenticator"
            });
          }
        );
      });
    }
  );
});

// -------- VERIFY 2FA --------
app.post("/api/auth/verify-2fa", authenticateToken, (req, res) => {
  const userId = req.userId;
  const { otp, secret } = req.body;

  if (!otp) {
    return res.status(400).json({ error: "OTP code is required." });
  }

  db.query(
    "SELECT two_factor_secret FROM users WHERE id = ?",
    [userId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) return res.status(404).json({ error: "User not found." });

      const userSecret = secret || results[0].two_factor_secret;

      if (!userSecret) {
        return res.status(400).json({ error: "2FA setup not initiated." });
      }

      // Verify OTP
      const verified = speakeasy.totp.verify({
        secret: userSecret,
        encoding: 'base32',
        token: otp,
        window: 2 // Allow 2 time steps before/after
      });

      if (!verified) {
        return res.status(400).json({ error: "Invalid OTP code." });
      }

      // Enable 2FA
      db.query(
        "UPDATE users SET two_factor_enabled = 1 WHERE id = ?",
        [userId],
        (err) => {
          if (err) {
            console.error('2FA enable error:', err);
            return res.status(500).json({ error: "Failed to enable 2FA." });
          }

          logActivity(userId, '2fa_enabled', 'Two-factor authentication enabled');

          res.json({ 
            message: "2FA enabled successfully!",
            enabled: true
          });
        }
      );
    }
  );
});

// -------- DISABLE 2FA --------
app.post("/api/auth/disable-2fa", authenticateToken, (req, res) => {
  const userId = req.userId;

  db.query(
    "UPDATE users SET two_factor_enabled = 0, two_factor_secret = NULL WHERE id = ?",
    [userId],
    (err) => {
      if (err) {
        console.error('2FA disable error:', err);
        return res.status(500).json({ error: "Failed to disable 2FA." });
      }

      logActivity(userId, '2fa_disabled', 'Two-factor authentication disabled');

      res.json({ 
        message: "2FA disabled successfully.",
        enabled: false
      });
    }
  );
});

// ============================================
// PAYOUT ACCOUNTS ENDPOINTS (For Sellers)
// ============================================

// -------- GET PAYOUT ACCOUNTS --------
app.get("/api/seller/payout-accounts", authenticateToken, (req, res) => {
  const userId = req.userId;

  // Verify user is an approved seller
  db.query(
    "SELECT role, is_approved FROM users WHERE id = ?",
    [userId],
    (err, userResults) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (userResults.length === 0) return res.status(404).json({ error: "User not found." });

      const user = userResults[0];
      const isApprovedSeller = user.role === 'seller' && user.is_approved === 1;

      if (!isApprovedSeller) {
        return res.status(403).json({ error: "Only approved sellers can manage payout accounts." });
      }

      db.query(
        `SELECT id, bank_name, account_number, account_name, is_default, created_at 
         FROM payout_accounts 
         WHERE seller_id = ? 
         ORDER BY is_default DESC, created_at DESC`,
        [userId],
        (err, results) => {
          if (err) {
            console.error('Payout accounts fetch error:', err);
            return res.status(500).json({ error: "Database error." });
          }
          res.json({ accounts: results });
        }
      );
    }
  );
});

// -------- ADD PAYOUT ACCOUNT --------
app.post("/api/seller/payout-accounts", authenticateToken, (req, res) => {
  const userId = req.userId;
  const { bank_name, account_number, account_name } = req.body;

  if (!bank_name || !account_number || !account_name) {
    return res.status(400).json({ error: "All fields are required." });
  }

  // Verify user is an approved seller
  db.query(
    "SELECT role, is_approved FROM users WHERE id = ?",
    [userId],
    (err, userResults) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (userResults.length === 0) return res.status(404).json({ error: "User not found." });

      const user = userResults[0];
      const isApprovedSeller = user.role === 'seller' && user.is_approved === 1;

      if (!isApprovedSeller) {
        return res.status(403).json({ error: "Only approved sellers can add payout accounts." });
      }

      // Check if this is the first account (make it default)
      db.query(
        "SELECT COUNT(*) as count FROM payout_accounts WHERE seller_id = ?",
        [userId],
        (err, countResults) => {
          if (err) return res.status(500).json({ error: "Database error." });

          const isFirst = countResults[0].count === 0;

          db.query(
            `INSERT INTO payout_accounts 
             (seller_id, bank_name, account_number, account_name, is_default) 
             VALUES (?, ?, ?, ?, ?)`,
            [userId, bank_name, account_number, account_name, isFirst ? 1 : 0],
            (err, result) => {
              if (err) {
                console.error('Add payout account error:', err);
                return res.status(500).json({ error: "Failed to add payout account." });
              }

              logActivity(userId, 'payout_account_added', `Added payout account: ${bank_name}`);

              res.status(201).json({
                message: "Payout account added successfully!",
                account_id: result.insertId
              });
            }
          );
        }
      );
    }
  );
});

// -------- DELETE PAYOUT ACCOUNT --------
app.delete("/api/seller/payout-accounts/:accountId", authenticateToken, (req, res) => {
  const userId = req.userId;
  const accountId = req.params.accountId;

  // Verify ownership
  db.query(
    "SELECT * FROM payout_accounts WHERE id = ? AND seller_id = ?",
    [accountId, userId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Account not found or unauthorized." });
      }

      const account = results[0];

      db.query(
        "DELETE FROM payout_accounts WHERE id = ?",
        [accountId],
        (err) => {
          if (err) {
            console.error('Delete payout account error:', err);
            return res.status(500).json({ error: "Failed to delete account." });
          }

          logActivity(userId, 'payout_account_deleted', `Deleted payout account: ${account.bank_name}`);

          // If this was the default account, set another as default
          if (account.is_default === 1) {
            db.query(
              "UPDATE payout_accounts SET is_default = 1 WHERE seller_id = ? LIMIT 1",
              [userId],
              () => {}
            );
          }

          res.json({ message: "Payout account deleted successfully." });
        }
      );
    }
  );
});

// -------- SET DEFAULT PAYOUT ACCOUNT --------
app.post("/api/seller/payout-accounts/:accountId/set-default", authenticateToken, (req, res) => {
  const userId = req.userId;
  const accountId = req.params.accountId;

  // Verify ownership
  db.query(
    "SELECT * FROM payout_accounts WHERE id = ? AND seller_id = ?",
    [accountId, userId],
    (err, results) => {
      if (err) return res.status(500).json({ error: "Database error." });
      if (results.length === 0) {
        return res.status(404).json({ error: "Account not found or unauthorized." });
      }

      // Remove default from all accounts
      db.query(
        "UPDATE payout_accounts SET is_default = 0 WHERE seller_id = ?",
        [userId],
        (err) => {
          if (err) return res.status(500).json({ error: "Database error." });

          // Set new default
          db.query(
            "UPDATE payout_accounts SET is_default = 1 WHERE id = ?",
            [accountId],
            (err) => {
              if (err) {
                console.error('Set default account error:', err);
                return res.status(500).json({ error: "Failed to set default account." });
              }

              res.json({ message: "Default payout account updated." });
            }
          );
        }
      );
    }
  );
});