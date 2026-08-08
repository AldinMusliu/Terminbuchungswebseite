import { useState } from 'react';
import { AuthProvider } from './context/AuthContext';
import { useAuth } from './context/authHooks';
import Header from './components/Header';
import AuthSheet from './components/AuthSheet';
import MeineTermine from './components/MeineTermine';
import './App.css';

function AppContent() {
  const { user } = useAuth();
  const [authOpen, setAuthOpen] = useState(false);
  const [authMode, setAuthMode] = useState('login');
  const [termineOpen, setTermineOpen] = useState(false);

  return (
    <div className="app-shell">
      <Header
        user={user}
        onLoginClick={() => {
          setAuthMode('login');
          setAuthOpen(true);
        }}
        onAccountClick={() => setTermineOpen(true)}
      />

      <main className="app-placeholder">
        <p>Hier entsteht als Naechstes die Buchungsseite.</p>
      </main>

      {authOpen && <AuthSheet initialMode={authMode} onClose={() => setAuthOpen(false)} />}

      {termineOpen && <MeineTermine onClose={() => setTermineOpen(false)} />}
    </div>
  );
}

export default function App() {
  return (
    <AuthProvider>
      <AppContent />
    </AuthProvider>
  );
}
