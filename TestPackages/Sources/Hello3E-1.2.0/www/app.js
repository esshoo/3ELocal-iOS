const key = 'hello3e.counter';
const output = document.querySelector('#count');
const read = () => Number(localStorage.getItem(key) || 0);
const render = () => output.textContent = read();
document.querySelector('#increase').addEventListener('click', () => {
  localStorage.setItem(key, String(read() + 1));
  render();
});
document.querySelector('#reset').addEventListener('click', () => {
  localStorage.setItem(key, '0');
  render();
});
render();
