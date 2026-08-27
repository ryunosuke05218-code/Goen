// GOEN Webサイト共通: バックエンドAPI呼び出し・ログインセッション保持のヘルパー。
// ビルドツールを使わない素のJSで、各ページのscriptタグから直接呼び出す想定。

const SESSION_KEYS = {
  accessToken: 'goen_access_token',
  displayName: 'goen_user_display_name',
  email: 'goen_user_email',
};

async function apiRequest(method, path, { body, token } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;

  const res = await fetch(`${API_BASE_URL}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });

  const data = await res.json().catch(() => null);
  if (!res.ok) {
    const message = data?.message || data?.title || `リクエストに失敗しました（${res.status}）`;
    throw new Error(message);
  }
  return data;
}

const apiPost = (path, body, token) => apiRequest('POST', path, { body, token });
const apiGet = (path, token) => apiRequest('GET', path, { token });

function saveSession(auth) {
  localStorage.setItem(SESSION_KEYS.accessToken, auth.accessToken);
  localStorage.setItem(SESSION_KEYS.displayName, auth.user.displayName);
  localStorage.setItem(SESSION_KEYS.email, auth.user.email);
}

function getAccessToken() {
  return localStorage.getItem(SESSION_KEYS.accessToken);
}

function getDisplayName() {
  return localStorage.getItem(SESSION_KEYS.displayName);
}

function clearSession() {
  Object.values(SESSION_KEYS).forEach((key) => localStorage.removeItem(key));
}

// ログイン必須ページの先頭で呼ぶ。未ログインならログイン画面へ飛ばす。
function requireLogin() {
  const token = getAccessToken();
  if (!token) {
    window.location.href = 'login.html';
    return null;
  }
  return token;
}

function showError(el, err) {
  el.textContent = err instanceof Error ? err.message : String(err);
  el.hidden = false;
}
