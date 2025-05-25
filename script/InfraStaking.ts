import { ethers } from "ethers";
import * as dotenv from "dotenv";
import abi from "./abis/InfraStakingABI.json";

dotenv.config();
//old address 0x4F1b01b58fEE85B81266B2CD0174C82c90f097F7
//new address 0x9AED278FBCDca9878482148643B58E75CA46a634
const INFRA_STAKING_ADDRESS = "0x9AED278FBCDca9878482148643B58E75CA46a634";

const provider = new ethers.JsonRpcProvider(process.env.RPC_URL!);
const signer = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);
const contract = new ethers.Contract(INFRA_STAKING_ADDRESS, abi, signer);

async function main() {
    try {
        // Example: Stake 0.1 AVAX
        const tx = await contract.stake({ value: ethers.parseEther("0.001") });
        await tx.wait();
        console.log("✅ Stake submitted", tx.hash);

        // // Example: Request unlock
        // const unlockTx = await contract.requestUnlock();
        // await unlockTx.wait();
        // console.log("✅ Unlock requested", unlockTx.hash);

        // // Example: Claim

        // const claimTx = await contract.claimUnstakes();
        // await claimTx.wait();
        // console.log("✅ Claimed unstaked AVAX", claimTx.hash);
    } catch (err) {
        console.error("❌ Error:", err);
    }

    // Read sAVAX balance
    const balance = await contract.sAvaxBalance(signer.address);
    console.log("sAVAX balance:", ethers.formatEther(balance));
}

main().catch(console.error);
