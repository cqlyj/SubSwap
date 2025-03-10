# **P2P Subscription Economy dApp**

## **🎯 Problem:**

Traditional **subscription models (Netflix, Spotify, Patreon, etc.)** have:  
🔴 **No resellability** – If you cancel early, you lose access with no refunds.  
🔴 **High platform fees** – Middlemen (Apple, Google, Patreon) take 15-30%.  
🔴 **Lack of transparency** – No on-chain proof of how payments are distributed.  
🔴 **Limited sharing** – Users can’t legally transfer unused subscriptions.

## **💡 Solution:**

A **Web3-powered subscription marketplace** where:  
✅ **Users can buy, sell, or share subscriptions** as **NFTs.**  
✅ **Smart contracts handle recurring payments** via stablecoins like **USDC.**  
✅ **Subscription owners can resell access** to others before expiration.  
✅ **Content creators receive fair payments** without platform middlemen.

---

# **🛠 How It Works**

### **1️⃣ Subscription NFTs (SFTs)**

- Instead of centralized accounts, users **own subscriptions as Semi-Fungible Tokens (ERC-1155 SFTs).**
- Each NFT represents **a subscription period** (e.g., 1-month Netflix access).
- **Users can transfer or resell** these NFTs before they expire.

### **2️⃣ Payment & Automation**

- **Stablecoins (USDC on Polygon/Arbitrum)** handle **recurring payments.**
- Smart contracts **auto-renew subscriptions** if the user has sufficient balance.
- Users can choose **one-time payments, auto-renewal, or P2P transfer.**

### **3️⃣ P2P Marketplace**

- Users who **don’t need the subscription anymore** can **list it for sale.**
- New buyers can **purchase unused subscription periods at a discount.**
- This enables **secondary markets** for digital services, reducing waste.

### **4️⃣ Revenue Distribution & Transparency**

- Smart contracts ensure **creators receive a fair share** instantly.
- **No middlemen fees** (Apple/Google usually take 15-30%).
- Users can see **transparent on-chain revenue distribution.**

---

# **🛠 Tech Stack & Protocols**

| Feature               | Protocol Used               | Why?                                     |
| --------------------- | --------------------------- | ---------------------------------------- |
| **Subscription NFTs** | **Polygon (ERC-1155 SFTs)** | Gas-efficient and scalable.              |
| **Resale & Swaps**    | **Uniswap Foundation**      | Users can swap subscriptions for tokens. |

---

# **🔹 Example User Scenarios**

### **🎬 Netflix User Reselling Extra Months**

- Alice **buys a 6-month Netflix subscription NFT** but only uses 3 months.
- She **lists her remaining 3 months** on the dApp marketplace.
- Bob buys the remaining 3 months **at a discounted price.**
- **Netflix still gets paid** via the smart contract, avoiding revenue loss.

### **🎵 Spotify Family Plan Splitting**

- John **subscribes to a Spotify Family Plan** but only needs 2 slots.
- He **resells 3 unused slots** to others, reducing his monthly cost.
- Each user **gets their own NFT**, ensuring fair and trackable access.

### **🎨 Patreon Creator Monetization**

- A Patreon-like creator issues **"exclusive access NFTs."**
- Fans **purchase these NFTs** to access premium content.
- **They can resell them** if they no longer want access.

---

# **🎯 Why This Idea Is Powerful**

✅ **Gives power to users** – No wasted subscriptions, full ownership.  
✅ **Fair creator payments** – No greedy middlemen fees.  
✅ **More flexible economy** – Users can **trade, resell, or gift** subscriptions.  
✅ **Cross-platform integration** – Works for streaming, gaming, AI tools, etc.

---

# **Tech Stack & Protocols for SubSwap**

## **1. Subscription Tokenization**

**Protocol:** ERC-1155 Semi-Fungible Tokens (SFTs) on Polygon

**Purpose:** To represent subscription periods as tokens that can be transferred, resold, or shared among users.

**Details:**

- **ERC-1155 Standard:** This standard allows for the creation of both fungible and non-fungible tokens within a single contract, making it efficient for managing multiple subscription types.

- **Polygon Network:** Deploying ERC-1155 contracts on Polygon offers scalability and lower transaction fees, enhancing the user experience.

## **2. Decentralized Marketplace Functionality**

**Protocol:** Uniswap Foundation

**Purpose:** To enable users to trade or swap subscription tokens in a decentralized manner.

**Details:**

- **Token Swaps:** Integrating with Uniswap allows users to exchange their subscription tokens for other assets or vice versa, providing liquidity and flexibility.

---

# **Profit Strategies**

### **Marketplace Transaction Fee (1-5%)**

- Charge a **small fee on every transaction** that occurs in the marketplace.
- This is **lower than centralized platforms** (which take 15-30%), making it fair.
- Example: If Bob buys a Netflix subscription NFT for **$10 USDC**, SubSwap **takes 3% ($0.30)** as a fee.

# Test

Just run the following command to test the code:

```bash
make test-sepolia
```
