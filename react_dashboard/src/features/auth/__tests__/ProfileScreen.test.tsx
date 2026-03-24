import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '../../../test/test-utils';
import ProfileScreen from '../screens/ProfileScreen';
import { authApi } from '../api/authApi';
import { useAuthStore } from '../store/authStore';

// Mock authApi
vi.mock('../api/authApi', () => ({
  authApi: {
    enable2FA: vi.fn(),
    verify2FA: vi.fn(),
    disable2FA: vi.fn(),
    enable2FAEmail: vi.fn(),
    verify2FAEmail: vi.fn(),
    resend2FACode: vi.fn(),
    changePassword: vi.fn(),
  },
}));

// Mock qrcode.react
vi.mock('qrcode.react', () => ({
  QRCodeSVG: ({ value }: { value: string }) => <div data-testid="qr-code">{value}</div>,
}));

// Mock window.confirm
const mockConfirm = vi.fn(() => true);
vi.stubGlobal('confirm', mockConfirm);

const adminUser = {
  id: '1',
  email: 'admin@schooltrack.be',
  role: 'DIRECTION' as const,
  first_name: 'Admin',
  last_name: 'Test',
  is_2fa_enabled: false,
  two_fa_method: null as string | null,
};

const adminWith2FAApp = {
  ...adminUser,
  is_2fa_enabled: true,
  two_fa_method: 'APP',
};

const adminWith2FAEmail = {
  ...adminUser,
  is_2fa_enabled: true,
  two_fa_method: 'EMAIL',
};

beforeEach(() => {
  vi.clearAllMocks();
  mockConfirm.mockReturnValue(true);
});

// =================================================================
// Informations utilisateur
// =================================================================

describe('ProfileScreen — Informations utilisateur', () => {
  it('affiche le nom, email et role de l\'utilisateur', () => {
    useAuthStore.setState({ token: 'test', user: adminUser });
    render(<ProfileScreen />);

    expect(screen.getByText('Mon Profil')).toBeInTheDocument();
    expect(screen.getByText('Admin Test')).toBeInTheDocument();
    expect(screen.getByText('admin@schooltrack.be')).toBeInTheDocument();
    expect(screen.getByText('DIRECTION')).toBeInTheDocument();
  });

  it('affiche les initiales dans l\'avatar', () => {
    useAuthStore.setState({ token: 'test', user: adminUser });
    render(<ProfileScreen />);
    expect(screen.getByText('AT')).toBeInTheDocument();
  });
});

// =================================================================
// 2FA — Etat desactivee
// =================================================================

describe('ProfileScreen — 2FA desactivee', () => {
  beforeEach(() => {
    useAuthStore.setState({ token: 'test', user: adminUser });
  });

  it('affiche le badge "Desactivee" et le bouton "Activer la 2FA"', () => {
    render(<ProfileScreen />);
    expect(screen.getByText('Desactivee')).toBeInTheDocument();
    expect(screen.getByText('Activer la 2FA')).toBeInTheDocument();
  });

  it('n\'affiche pas le bouton "Desactiver"', () => {
    render(<ProfileScreen />);
    expect(screen.queryByText('Desactiver')).not.toBeInTheDocument();
  });
});

// =================================================================
// 2FA — Pre-etape de choix de methode
// =================================================================

describe('ProfileScreen — Choix de methode 2FA', () => {
  beforeEach(() => {
    useAuthStore.setState({ token: 'test', user: adminUser });
  });

  it('affiche les deux options (Application et Email) apres clic sur Activer', () => {
    render(<ProfileScreen />);
    fireEvent.click(screen.getByText('Activer la 2FA'));

    expect(screen.getByText('Application')).toBeInTheDocument();
    expect(screen.getByText('Email')).toBeInTheDocument();
    expect(screen.getByText('Google Authenticator, Authy, etc.')).toBeInTheDocument();
  });

  it('permet d\'annuler et revenir a l\'etat idle', () => {
    render(<ProfileScreen />);
    fireEvent.click(screen.getByText('Activer la 2FA'));
    expect(screen.getByText('Application')).toBeInTheDocument();

    fireEvent.click(screen.getByText('Annuler'));
    expect(screen.getByText('Activer la 2FA')).toBeInTheDocument();
  });
});

// =================================================================
// 2FA — Activation par Application (APP)
// =================================================================

describe('ProfileScreen — Activation 2FA par Application', () => {
  beforeEach(() => {
    useAuthStore.setState({ token: 'test', user: adminUser });
  });

  it('affiche le QR code apres choix "Application"', async () => {
    vi.mocked(authApi.enable2FA).mockResolvedValue({
      secret: 'JBSWY3DPEHPK3PXP',
      provisioning_uri: 'otpauth://totp/admin@schooltrack.be?secret=JBSWY3DPEHPK3PXP&issuer=SchoolTrack',
    });

    render(<ProfileScreen />);
    fireEvent.click(screen.getByText('Activer la 2FA'));
    fireEvent.click(screen.getByText('Application'));

    await waitFor(() => {
      expect(screen.getByTestId('qr-code')).toBeInTheDocument();
    });
    expect(screen.getByText('JBSWY3DPEHPK3PXP')).toBeInTheDocument();
  });

  it('active la 2FA apres verification du code TOTP', async () => {
    vi.mocked(authApi.enable2FA).mockResolvedValue({
      secret: 'JBSWY3DPEHPK3PXP',
      provisioning_uri: 'otpauth://totp/test',
    });
    vi.mocked(authApi.verify2FA).mockResolvedValue({ message: 'ok' });

    render(<ProfileScreen />);
    fireEvent.click(screen.getByText('Activer la 2FA'));
    fireEvent.click(screen.getByText('Application'));

    await waitFor(() => {
      expect(screen.getByText('Suivant', { exact: false })).toBeInTheDocument();
    });
    fireEvent.click(screen.getByText('Suivant', { exact: false }));

    const input = screen.getByLabelText('Code 2FA (6 chiffres)');
    fireEvent.change(input, { target: { value: '123456' } });
    fireEvent.click(screen.getByText('Verifier et activer'));

    await waitFor(() => {
      expect(screen.getByText('2FA par application activee avec succes !')).toBeInTheDocument();
    });
    expect(authApi.verify2FA).toHaveBeenCalledWith('123456');
    expect(useAuthStore.getState().user?.is_2fa_enabled).toBe(true);
    expect(useAuthStore.getState().user?.two_fa_method).toBe('APP');
  });

  it('affiche une erreur si le code TOTP est invalide', async () => {
    vi.mocked(authApi.enable2FA).mockResolvedValue({
      secret: 'JBSWY3DPEHPK3PXP',
      provisioning_uri: 'otpauth://totp/test',
    });
    vi.mocked(authApi.verify2FA).mockRejectedValue({
      response: { data: { detail: 'Code 2FA invalide' } },
    });

    render(<ProfileScreen />);
    fireEvent.click(screen.getByText('Activer la 2FA'));
    fireEvent.click(screen.getByText('Application'));

    await waitFor(() => {
      expect(screen.getByText('Suivant', { exact: false })).toBeInTheDocument();
    });
    fireEvent.click(screen.getByText('Suivant', { exact: false }));

    fireEvent.change(screen.getByLabelText('Code 2FA (6 chiffres)'), { target: { value: '000000' } });
    fireEvent.click(screen.getByText('Verifier et activer'));

    await waitFor(() => {
      expect(screen.getByText('Code 2FA invalide')).toBeInTheDocument();
    });
  });

  it('le bouton verifier est desactive si code < 6 chiffres', async () => {
    vi.mocked(authApi.enable2FA).mockResolvedValue({
      secret: 'JBSWY3DPEHPK3PXP',
      provisioning_uri: 'otpauth://totp/test',
    });

    render(<ProfileScreen />);
    fireEvent.click(screen.getByText('Activer la 2FA'));
    fireEvent.click(screen.getByText('Application'));

    await waitFor(() => {
      expect(screen.getByText('Suivant', { exact: false })).toBeInTheDocument();
    });
    fireEvent.click(screen.getByText('Suivant', { exact: false }));

    fireEvent.change(screen.getByLabelText('Code 2FA (6 chiffres)'), { target: { value: '123' } });
    expect(screen.getByText('Verifier et activer').closest('button')).toBeDisabled();
  });

  it('permet de retourner au QR code depuis la verification', async () => {
    vi.mocked(authApi.enable2FA).mockResolvedValue({
      secret: 'JBSWY3DPEHPK3PXP',
      provisioning_uri: 'otpauth://totp/test',
    });

    render(<ProfileScreen />);
    fireEvent.click(screen.getByText('Activer la 2FA'));
    fireEvent.click(screen.getByText('Application'));

    await waitFor(() => {
      expect(screen.getByText('Suivant', { exact: false })).toBeInTheDocument();
    });
    fireEvent.click(screen.getByText('Suivant', { exact: false }));
    fireEvent.click(screen.getByText('Retour'));

    expect(screen.getByTestId('qr-code')).toBeInTheDocument();
  });
});

// =================================================================
// 2FA — Activation par Email
// =================================================================

describe('ProfileScreen — Activation 2FA par Email', () => {
  beforeEach(() => {
    useAuthStore.setState({ token: 'test', user: adminUser });
  });

  it('affiche le formulaire email OTP apres choix "Email"', async () => {
    vi.mocked(authApi.enable2FAEmail).mockResolvedValue({ message: 'Code envoye' });

    render(<ProfileScreen />);
    fireEvent.click(screen.getByText('Activer la 2FA'));
    fireEvent.click(screen.getByText('Email'));

    await waitFor(() => {
      expect(screen.getByText('Code envoye par email', { exact: false })).toBeInTheDocument();
    });
    expect(screen.getByLabelText('Code de verification (6 chiffres)')).toBeInTheDocument();
  });

  it('active la 2FA par email apres verification du code', async () => {
    vi.mocked(authApi.enable2FAEmail).mockResolvedValue({ message: 'ok' });
    vi.mocked(authApi.verify2FAEmail).mockResolvedValue({ message: 'ok' });

    render(<ProfileScreen />);
    fireEvent.click(screen.getByText('Activer la 2FA'));
    fireEvent.click(screen.getByText('Email'));

    await waitFor(() => {
      expect(screen.getByLabelText('Code de verification (6 chiffres)')).toBeInTheDocument();
    });

    fireEvent.change(screen.getByLabelText('Code de verification (6 chiffres)'), { target: { value: '654321' } });
    fireEvent.click(screen.getByText('Verifier et activer'));

    await waitFor(() => {
      expect(screen.getByText('2FA par email activee avec succes !')).toBeInTheDocument();
    });
    expect(authApi.verify2FAEmail).toHaveBeenCalledWith('654321');
    expect(useAuthStore.getState().user?.is_2fa_enabled).toBe(true);
    expect(useAuthStore.getState().user?.two_fa_method).toBe('EMAIL');
  });

  it('affiche une erreur si le code email est invalide', async () => {
    vi.mocked(authApi.enable2FAEmail).mockResolvedValue({ message: 'ok' });
    vi.mocked(authApi.verify2FAEmail).mockRejectedValue({
      response: { data: { detail: 'Code invalide' } },
    });

    render(<ProfileScreen />);
    fireEvent.click(screen.getByText('Activer la 2FA'));
    fireEvent.click(screen.getByText('Email'));

    await waitFor(() => {
      expect(screen.getByLabelText('Code de verification (6 chiffres)')).toBeInTheDocument();
    });

    fireEvent.change(screen.getByLabelText('Code de verification (6 chiffres)'), { target: { value: '000000' } });
    fireEvent.click(screen.getByText('Verifier et activer'));

    await waitFor(() => {
      expect(screen.getByText('Code invalide')).toBeInTheDocument();
    });
  });

  it('permet de renvoyer le code', async () => {
    vi.mocked(authApi.enable2FAEmail).mockResolvedValue({ message: 'ok' });
    vi.mocked(authApi.resend2FACode).mockResolvedValue({ message: 'ok' });

    render(<ProfileScreen />);
    fireEvent.click(screen.getByText('Activer la 2FA'));
    fireEvent.click(screen.getByText('Email'));

    await waitFor(() => {
      expect(screen.getByText('Renvoyer le code')).toBeInTheDocument();
    });
    fireEvent.click(screen.getByText('Renvoyer le code'));

    await waitFor(() => {
      expect(authApi.resend2FACode).toHaveBeenCalled();
    });
  });

  it('permet de retourner au choix depuis la verification email', async () => {
    vi.mocked(authApi.enable2FAEmail).mockResolvedValue({ message: 'ok' });

    render(<ProfileScreen />);
    fireEvent.click(screen.getByText('Activer la 2FA'));
    fireEvent.click(screen.getByText('Email'));

    await waitFor(() => {
      expect(screen.getByText('Retour')).toBeInTheDocument();
    });
    fireEvent.click(screen.getByText('Retour'));

    expect(screen.getByText('Application')).toBeInTheDocument();
    expect(screen.getByText('Email')).toBeInTheDocument();
  });
});

// =================================================================
// 2FA — Etat activee / Desactivation
// =================================================================

describe('ProfileScreen — 2FA activee / Desactivation', () => {
  it('affiche le badge "Activee (App)" pour methode APP', () => {
    useAuthStore.setState({ token: 'test', user: adminWith2FAApp });
    render(<ProfileScreen />);

    expect(screen.getByText('Activee (App)')).toBeInTheDocument();
    expect(screen.getByText('Desactiver')).toBeInTheDocument();
  });

  it('affiche le badge "Activee (Email)" pour methode EMAIL', () => {
    useAuthStore.setState({ token: 'test', user: adminWith2FAEmail });
    render(<ProfileScreen />);

    expect(screen.getByText('Activee (Email)')).toBeInTheDocument();
  });

  it('n\'affiche pas le bouton "Activer la 2FA"', () => {
    useAuthStore.setState({ token: 'test', user: adminWith2FAApp });
    render(<ProfileScreen />);
    expect(screen.queryByText('Activer la 2FA')).not.toBeInTheDocument();
  });

  it('desactive la 2FA apres confirmation', async () => {
    useAuthStore.setState({ token: 'test', user: adminWith2FAApp });
    vi.mocked(authApi.disable2FA).mockResolvedValue({ message: 'ok' });

    render(<ProfileScreen />);
    fireEvent.click(screen.getByText('Desactiver'));

    expect(mockConfirm).toHaveBeenCalled();

    await waitFor(() => {
      expect(screen.getByText('2FA desactivee.')).toBeInTheDocument();
    });
    expect(useAuthStore.getState().user?.is_2fa_enabled).toBe(false);
    expect(useAuthStore.getState().user?.two_fa_method).toBeNull();
  });

  it('annule la desactivation si l\'utilisateur refuse', () => {
    useAuthStore.setState({ token: 'test', user: adminWith2FAApp });
    mockConfirm.mockReturnValue(false);

    render(<ProfileScreen />);
    fireEvent.click(screen.getByText('Desactiver'));

    expect(mockConfirm).toHaveBeenCalled();
    expect(authApi.disable2FA).not.toHaveBeenCalled();
  });
});

// =================================================================
// Changement de mot de passe
// =================================================================

describe('ProfileScreen — Changement de mot de passe', () => {
  beforeEach(() => {
    useAuthStore.setState({ token: 'test', user: adminUser });
  });

  it('affiche les champs de mot de passe', () => {
    render(<ProfileScreen />);
    expect(screen.getByLabelText('Mot de passe actuel')).toBeInTheDocument();
    expect(screen.getByLabelText('Nouveau mot de passe')).toBeInTheDocument();
    expect(screen.getByLabelText('Confirmer le nouveau mot de passe')).toBeInTheDocument();
  });

  it('le bouton est desactive quand les champs sont vides', () => {
    render(<ProfileScreen />);
    expect(screen.getByText('Modifier le mot de passe').closest('button')).toBeDisabled();
  });

  it('affiche une erreur si les mots de passe ne correspondent pas', () => {
    render(<ProfileScreen />);
    fireEvent.change(screen.getByLabelText('Mot de passe actuel'), { target: { value: 'OldPass1!' } });
    fireEvent.change(screen.getByLabelText('Nouveau mot de passe'), { target: { value: 'NewPass1!' } });
    fireEvent.change(screen.getByLabelText('Confirmer le nouveau mot de passe'), { target: { value: 'Different1!' } });
    fireEvent.click(screen.getByText('Modifier le mot de passe'));

    expect(screen.getByText('Les mots de passe ne correspondent pas')).toBeInTheDocument();
  });

  it('affiche une erreur si le mot de passe est trop court', () => {
    render(<ProfileScreen />);
    fireEvent.change(screen.getByLabelText('Mot de passe actuel'), { target: { value: 'OldPass1!' } });
    fireEvent.change(screen.getByLabelText('Nouveau mot de passe'), { target: { value: 'Ab1!' } });
    fireEvent.change(screen.getByLabelText('Confirmer le nouveau mot de passe'), { target: { value: 'Ab1!' } });
    fireEvent.click(screen.getByText('Modifier le mot de passe'));

    expect(screen.getByText('Le nouveau mot de passe doit contenir au moins 8 caracteres')).toBeInTheDocument();
  });

  it('change le mot de passe avec succes', async () => {
    vi.mocked(authApi.changePassword).mockResolvedValue({ message: 'ok' });

    render(<ProfileScreen />);
    fireEvent.change(screen.getByLabelText('Mot de passe actuel'), { target: { value: 'OldPass1!' } });
    fireEvent.change(screen.getByLabelText('Nouveau mot de passe'), { target: { value: 'NewPass1!' } });
    fireEvent.change(screen.getByLabelText('Confirmer le nouveau mot de passe'), { target: { value: 'NewPass1!' } });
    fireEvent.click(screen.getByText('Modifier le mot de passe'));

    await waitFor(() => {
      expect(screen.getByText('Mot de passe modifie avec succes.')).toBeInTheDocument();
    });
    expect(authApi.changePassword).toHaveBeenCalledWith('OldPass1!', 'NewPass1!');
  });

  it('affiche une erreur si l\'ancien mot de passe est incorrect', async () => {
    vi.mocked(authApi.changePassword).mockRejectedValue({
      response: { data: { detail: 'Mot de passe actuel incorrect' } },
    });

    render(<ProfileScreen />);
    fireEvent.change(screen.getByLabelText('Mot de passe actuel'), { target: { value: 'WrongPass!' } });
    fireEvent.change(screen.getByLabelText('Nouveau mot de passe'), { target: { value: 'NewPass1!' } });
    fireEvent.change(screen.getByLabelText('Confirmer le nouveau mot de passe'), { target: { value: 'NewPass1!' } });
    fireEvent.click(screen.getByText('Modifier le mot de passe'));

    await waitFor(() => {
      expect(screen.getByText('Mot de passe actuel incorrect')).toBeInTheDocument();
    });
  });
});
