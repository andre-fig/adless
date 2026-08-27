declare module "*.txt" {
  const content: string;
  export default content;
}

declare module "*.json" {
  const content: {
    schemaVersion: number;
    version: string;
    domainCount: number;
    textSHA256?: string;
  };
  export default content;
}
