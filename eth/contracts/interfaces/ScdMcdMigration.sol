pragma solidity 0.5.13;

interface ScdMcdMigration {
  // Function to swap SAI to DAI
  // This function is to be used by users that want to get new DAI in exchange of old one (aka SAI)
  // wad amount has to be <= the value pending to reach the debt ceiling (the minimum between general and ilk one)
  function swapSaiToDai(
    uint wad
  ) external;
}