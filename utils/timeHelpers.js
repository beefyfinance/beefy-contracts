const nowInSeconds = () => {
  return parseInt(Date.now() / 1000);
};

const delay = ms => new Promise(res => setTimeout(res, ms));

module.exports = {
  nowInSeconds,
  delay
};
