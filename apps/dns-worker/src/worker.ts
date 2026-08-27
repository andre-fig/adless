import blocklistText from "../data/blocklist.txt";
import metadata from "../data/blocklist.meta.json";
import { createDNSWorker } from "./handler.js";
import { StatsDurableObject } from "./stats.js";

export { StatsDurableObject };
export default createDNSWorker(blocklistText, metadata);
