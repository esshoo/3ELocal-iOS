document.querySelector('#test').addEventListener('click', () => {
  document.querySelector('#result').textContent = `JavaScript works — ${new Date().toLocaleTimeString()}`;
});
