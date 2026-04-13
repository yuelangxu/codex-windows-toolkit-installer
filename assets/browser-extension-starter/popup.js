const hashValue = document.getElementById("hash-value");
const status = document.getElementById("status");
const actionButton = document.getElementById("starter-action");

function refreshHash() {
  const value = window.location.hash || "none";
  hashValue.textContent = value;
}

actionButton.addEventListener("click", () => {
  window.location.hash = "clicked";
  status.setAttribute("data-clicked", "true");
  refreshHash();
});

refreshHash();
