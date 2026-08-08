import './Header.css';

export default function Header({ user, onLoginClick, onAccountClick }) {
  const initiale = (user?.user_metadata?.full_name || user?.email || '?').trim().charAt(0).toUpperCase();

  return (
    <header className="app-header">
      <div className="brand">
        <div className="logo-badge">R</div>
        <span className="brand-name">Rajana Beauty</span>
      </div>

      {user ? (
        <button
          type="button"
          className="avatar-btn"
          onClick={onAccountClick}
          aria-label="Meine Termine"
        >
          {initiale}
        </button>
      ) : (
        <button type="button" className="btn-login" onClick={onLoginClick}>
          Login
        </button>
      )}
    </header>
  );
}
