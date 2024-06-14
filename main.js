const { readFileSync } = require("fs");

function main() {
  const buffer = readFileSync(
    "./script.mv"
  );
  let bytecode = buffer.toString("hex");

  console.log("By ", bytecode);
}

main();
