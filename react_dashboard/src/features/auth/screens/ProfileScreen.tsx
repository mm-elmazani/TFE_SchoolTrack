import { useState } from 'react';
import { useMutation } from '@tanstack/react-query';
import { QRCodeSVG } from 'qrcode.react';
import { useAuthStore } from '../store/authStore';
import { authApi, type Enable2FAResponse } from '../api/authApi';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import {
  ShieldCheck,
  ShieldOff,
  Loader2,
  CheckCircle,
  AlertCircle,
  User as UserIcon,
  Mail,
  Lock,
  Eye,
  EyeOff,
  Copy,
  KeyRound,
  Smartphone,
} from 'lucide-react';
import { cn } from '@/lib/utils';

type TwoFAStep = 'idle' | 'choose' | 'qr' | 'verify-app' | 'email-sent' | 'verify-email' | 'done';

export default function ProfileScreen() {
  const { user, updateUser } = useAuthStore();

  // --- 2FA state ---
  const [twoFAStep, setTwoFAStep] = useState<TwoFAStep>('idle');
  const [twoFAData, setTwoFAData] = useState<Enable2FAResponse | null>(null);
  const [totpCode, setTotpCode] = useState('');
  const [twoFAError, setTwoFAError] = useState<string | null>(null);
  const [twoFASuccess, setTwoFASuccess] = useState<string | null>(null);
  const [secretCopied, setSecretCopied] = useState(false);

  // --- Change password state ---
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showCurrentPw, setShowCurrentPw] = useState(false);
  const [showNewPw, setShowNewPw] = useState(false);
  const [pwError, setPwError] = useState<string | null>(null);
  const [pwSuccess, setPwSuccess] = useState<string | null>(null);

  // --- Mutations APP ---
  const enableAppMutation = useMutation({
    mutationFn: authApi.enable2FA,
    onSuccess: (data) => {
      setTwoFAData(data);
      setTwoFAStep('qr');
      setTwoFAError(null);
    },
    onError: (err: any) => {
      setTwoFAError(err.response?.data?.detail || 'Erreur lors de l\'activation');
    },
  });

  const verifyAppMutation = useMutation({
    mutationFn: (code: string) => authApi.verify2FA(code),
    onSuccess: () => {
      setTwoFAStep('done');
      setTwoFAError(null);
      setTwoFASuccess('2FA par application activee avec succes !');
      updateUser({ is_2fa_enabled: true, two_fa_method: 'APP' });
      setTotpCode('');
    },
    onError: (err: any) => {
      setTwoFAError(err.response?.data?.detail || 'Code invalide');
    },
  });

  // --- Mutations EMAIL ---
  const enableEmailMutation = useMutation({
    mutationFn: authApi.enable2FAEmail,
    onSuccess: () => {
      setTwoFAStep('verify-email');
      setTwoFAError(null);
    },
    onError: (err: any) => {
      setTwoFAError(err.response?.data?.detail || 'Erreur lors de l\'envoi du code');
    },
  });

  const verifyEmailMutation = useMutation({
    mutationFn: (code: string) => authApi.verify2FAEmail(code),
    onSuccess: () => {
      setTwoFAStep('done');
      setTwoFAError(null);
      setTwoFASuccess('2FA par email activee avec succes !');
      updateUser({ is_2fa_enabled: true, two_fa_method: 'EMAIL' });
      setTotpCode('');
    },
    onError: (err: any) => {
      setTwoFAError(err.response?.data?.detail || 'Code invalide ou expire');
    },
  });

  const resendCodeMutation = useMutation({
    mutationFn: authApi.resend2FACode,
    onSuccess: () => { setTwoFAError(null); setTwoFASuccess('Nouveau code envoye !'); },
    onError: (err: any) => { setTwoFAError(err.response?.data?.detail || 'Erreur'); },
  });

  const disableMutation = useMutation({
    mutationFn: authApi.disable2FA,
    onSuccess: () => {
      setTwoFASuccess('2FA desactivee.');
      setTwoFAError(null);
      updateUser({ is_2fa_enabled: false, two_fa_method: null });
      setTwoFAStep('idle');
      setTwoFAData(null);
    },
    onError: (err: any) => {
      setTwoFAError(err.response?.data?.detail || 'Erreur lors de la desactivation');
    },
  });

  const changePasswordMutation = useMutation({
    mutationFn: () => authApi.changePassword(currentPassword, newPassword),
    onSuccess: () => {
      setPwSuccess('Mot de passe modifie avec succes.');
      setPwError(null);
      setCurrentPassword('');
      setNewPassword('');
      setConfirmPassword('');
    },
    onError: (err: any) => {
      setPwError(err.response?.data?.detail || 'Erreur lors du changement');
      setPwSuccess(null);
    },
  });

  // --- Handlers ---
  const handleStartEnable = () => {
    setTwoFAError(null);
    setTwoFASuccess(null);
    setTotpCode('');
    setTwoFAStep('choose');
  };

  const handleChooseApp = () => {
    setTwoFAError(null);
    enableAppMutation.mutate();
  };

  const handleChooseEmail = () => {
    setTwoFAError(null);
    enableEmailMutation.mutate();
  };

  const handleVerifyApp = () => {
    if (totpCode.length !== 6) {
      setTwoFAError('Le code doit contenir 6 chiffres');
      return;
    }
    verifyAppMutation.mutate(totpCode);
  };

  const handleVerifyEmail = () => {
    if (totpCode.length !== 6) {
      setTwoFAError('Le code doit contenir 6 chiffres');
      return;
    }
    setTwoFASuccess(null);
    verifyEmailMutation.mutate(totpCode);
  };

  const handleDisable2FA = () => {
    if (!confirm('Desactiver l\'authentification a deux facteurs ? Votre compte sera moins securise.')) return;
    disableMutation.mutate();
  };

  const handleChangePassword = () => {
    setPwError(null);
    setPwSuccess(null);
    if (!currentPassword || !newPassword) {
      setPwError('Tous les champs sont requis');
      return;
    }
    if (newPassword.length < 8) {
      setPwError('Le nouveau mot de passe doit contenir au moins 8 caracteres');
      return;
    }
    if (newPassword !== confirmPassword) {
      setPwError('Les mots de passe ne correspondent pas');
      return;
    }
    changePasswordMutation.mutate();
  };

  const copySecret = () => {
    if (twoFAData?.secret) {
      navigator.clipboard.writeText(twoFAData.secret);
      setSecretCopied(true);
      setTimeout(() => setSecretCopied(false), 2000);
    }
  };

  const is2FAEnabled = user?.is_2fa_enabled === true;
  const isEnabling = twoFAStep === 'choose' || twoFAStep === 'qr' || twoFAStep === 'verify-app' || twoFAStep === 'verify-email';

  return (
    <div className="space-y-6 max-w-2xl">
      {/* Header */}
      <div className="flex flex-col gap-1">
        <h2 className="text-3xl font-bold tracking-tight text-schooltrack-primary font-heading">Mon Profil</h2>
        <p className="text-slate-500 font-sans">Gerez votre compte et la securite de votre acces.</p>
      </div>

      {/* Informations utilisateur */}
      <Card className="border-slate-200 shadow-sm rounded-2xl">
        <CardHeader className="pb-4">
          <CardTitle className="text-lg font-heading text-schooltrack-primary flex items-center gap-2">
            <UserIcon className="w-5 h-5" />
            Informations
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="flex items-center gap-3 p-3 bg-slate-50 rounded-xl">
            <div className="w-12 h-12 bg-schooltrack-primary rounded-full flex items-center justify-center text-white font-bold text-lg shadow-md">
              {user?.first_name?.[0]}{user?.last_name?.[0]}
            </div>
            <div>
              <p className="font-semibold text-slate-900">{user?.first_name} {user?.last_name}</p>
              <div className="flex items-center gap-2 mt-0.5">
                <Mail className="w-3.5 h-3.5 text-slate-400" />
                <span className="text-sm text-slate-600">{user?.email}</span>
              </div>
            </div>
            <Badge className="ml-auto uppercase text-[10px] tracking-wider font-semibold bg-schooltrack-primary text-white">
              {user?.role}
            </Badge>
          </div>
        </CardContent>
      </Card>

      {/* Section 2FA */}
      <Card className="border-slate-200 shadow-sm rounded-2xl">
        <CardHeader className="pb-4">
          <div className="flex items-center justify-between">
            <div>
              <CardTitle className="text-lg font-heading text-schooltrack-primary flex items-center gap-2">
                <KeyRound className="w-5 h-5" />
                Authentification a deux facteurs (2FA)
              </CardTitle>
              <CardDescription className="mt-1">
                Protegez votre compte avec une verification supplementaire a chaque connexion.
              </CardDescription>
            </div>
            <Badge className={cn(
              "text-xs font-semibold",
              is2FAEnabled
                ? "bg-green-50 text-green-700 border-green-200"
                : "bg-slate-100 text-slate-500 border-slate-200"
            )}>
              {is2FAEnabled
                ? `Activee (${user?.two_fa_method === 'EMAIL' ? 'Email' : 'App'})`
                : 'Desactivee'}
            </Badge>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {/* Messages */}
          {twoFAError && (
            <div className="p-3 bg-red-50 text-red-700 border border-red-100 rounded-xl text-sm flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0" />
              {twoFAError}
            </div>
          )}
          {twoFASuccess && (
            <div className="p-3 bg-green-50 text-green-700 border border-green-100 rounded-xl text-sm flex items-center gap-2">
              <CheckCircle className="w-4 h-4 shrink-0" />
              {twoFASuccess}
            </div>
          )}

          {/* === IDLE : bouton Activer === */}
          {!is2FAEnabled && twoFAStep === 'idle' && (
            <Button
              onClick={handleStartEnable}
              className="bg-schooltrack-action hover:bg-blue-700 text-white rounded-xl h-11 px-6 shadow-md flex items-center gap-2"
            >
              <ShieldCheck className="w-4 h-4" />
              Activer la 2FA
            </Button>
          )}

          {/* === CHOOSE : choix de la methode === */}
          {twoFAStep === 'choose' && (
            <div className="space-y-3">
              <p className="text-sm text-slate-600 font-medium">Choisissez votre methode de verification :</p>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <button
                  onClick={handleChooseApp}
                  disabled={enableAppMutation.isPending}
                  className="flex flex-col items-center gap-3 p-5 border-2 border-slate-200 rounded-xl hover:border-schooltrack-primary hover:bg-blue-50/50 transition-all text-center group disabled:opacity-50"
                >
                  {enableAppMutation.isPending
                    ? <Loader2 className="w-8 h-8 text-schooltrack-primary animate-spin" />
                    : <Smartphone className="w-8 h-8 text-slate-400 group-hover:text-schooltrack-primary transition-colors" />}
                  <div>
                    <p className="font-semibold text-slate-800 group-hover:text-schooltrack-primary">Application</p>
                    <p className="text-xs text-slate-500 mt-1">Google Authenticator, Authy, etc.</p>
                  </div>
                </button>
                <button
                  onClick={handleChooseEmail}
                  disabled={enableEmailMutation.isPending}
                  className="flex flex-col items-center gap-3 p-5 border-2 border-slate-200 rounded-xl hover:border-schooltrack-primary hover:bg-blue-50/50 transition-all text-center group disabled:opacity-50"
                >
                  {enableEmailMutation.isPending
                    ? <Loader2 className="w-8 h-8 text-schooltrack-primary animate-spin" />
                    : <Mail className="w-8 h-8 text-slate-400 group-hover:text-schooltrack-primary transition-colors" />}
                  <div>
                    <p className="font-semibold text-slate-800 group-hover:text-schooltrack-primary">Email</p>
                    <p className="text-xs text-slate-500 mt-1">Code envoye a {user?.email}</p>
                  </div>
                </button>
              </div>
              <button
                type="button"
                onClick={() => { setTwoFAStep('idle'); setTwoFAError(null); }}
                className="w-full text-sm text-slate-500 hover:text-schooltrack-primary transition-colors mt-2"
              >
                Annuler
              </button>
            </div>
          )}

          {/* === QR : QR code pour methode APP === */}
          {twoFAStep === 'qr' && twoFAData && (
            <div className="space-y-4">
              <div className="p-4 bg-blue-50 border border-blue-100 rounded-xl text-sm text-blue-800">
                <p className="font-medium mb-1">Etape 1 : Scannez le QR code</p>
                <p>Ouvrez votre application d'authentification et scannez ce QR code.</p>
              </div>

              <div className="flex justify-center p-6 bg-white border border-slate-200 rounded-xl">
                <QRCodeSVG value={twoFAData.provisioning_uri} size={200} level="M" />
              </div>

              <div className="space-y-2">
                <p className="text-xs text-slate-500 font-medium">Ou entrez ce code manuellement :</p>
                <div className="flex items-center gap-2">
                  <code className="flex-1 p-3 bg-slate-100 rounded-lg text-sm font-mono text-slate-700 break-all select-all">
                    {twoFAData.secret}
                  </code>
                  <Button variant="outline" size="sm" onClick={copySecret} className="shrink-0 rounded-lg">
                    {secretCopied ? <CheckCircle className="w-4 h-4 text-green-600" /> : <Copy className="w-4 h-4" />}
                  </Button>
                </div>
              </div>

              <Button
                onClick={() => setTwoFAStep('verify-app')}
                className="w-full bg-schooltrack-primary hover:bg-blue-900 text-white rounded-xl h-11"
              >
                Suivant — Verifier le code
              </Button>
            </div>
          )}

          {/* === VERIFY-APP : saisie du code TOTP === */}
          {twoFAStep === 'verify-app' && (
            <div className="space-y-4">
              <div className="p-4 bg-blue-50 border border-blue-100 rounded-xl text-sm text-blue-800">
                <p className="font-medium mb-1">Etape 2 : Entrez le code de verification</p>
                <p>Saisissez le code a 6 chiffres affiche dans votre application d'authentification.</p>
              </div>

              <div className="space-y-2">
                <Label htmlFor="totp-verify" className="text-slate-700 font-medium">Code 2FA (6 chiffres)</Label>
                <Input
                  id="totp-verify"
                  type="text"
                  inputMode="numeric"
                  maxLength={6}
                  placeholder="000000"
                  autoFocus
                  value={totpCode}
                  onChange={(e) => setTotpCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
                  className="h-12 text-center text-2xl tracking-[0.5em] font-mono border-slate-200 rounded-xl"
                />
              </div>

              <div className="flex gap-3">
                <Button
                  variant="outline"
                  onClick={() => { setTwoFAStep('qr'); setTotpCode(''); setTwoFAError(null); }}
                  className="flex-1 rounded-xl h-11"
                >
                  Retour
                </Button>
                <Button
                  onClick={handleVerifyApp}
                  disabled={verifyAppMutation.isPending || totpCode.length !== 6}
                  className="flex-1 bg-schooltrack-primary hover:bg-blue-900 text-white rounded-xl h-11"
                >
                  {verifyAppMutation.isPending ? <Loader2 className="w-4 h-4 animate-spin mr-2" /> : null}
                  Verifier et activer
                </Button>
              </div>
            </div>
          )}

          {/* === VERIFY-EMAIL : saisie du code recu par email === */}
          {twoFAStep === 'verify-email' && (
            <div className="space-y-4">
              <div className="p-4 bg-blue-50 border border-blue-100 rounded-xl text-sm text-blue-800">
                <p className="font-medium mb-1">Code envoye par email</p>
                <p>Un code de verification a 6 chiffres a ete envoye a <strong>{user?.email}</strong>. Saisissez-le ci-dessous.</p>
              </div>

              <div className="space-y-2">
                <Label htmlFor="email-otp-verify" className="text-slate-700 font-medium">Code de verification (6 chiffres)</Label>
                <Input
                  id="email-otp-verify"
                  type="text"
                  inputMode="numeric"
                  maxLength={6}
                  placeholder="000000"
                  autoFocus
                  value={totpCode}
                  onChange={(e) => setTotpCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
                  className="h-12 text-center text-2xl tracking-[0.5em] font-mono border-slate-200 rounded-xl"
                />
              </div>

              <div className="flex gap-3">
                <Button
                  variant="outline"
                  onClick={() => { setTwoFAStep('choose'); setTotpCode(''); setTwoFAError(null); setTwoFASuccess(null); }}
                  className="flex-1 rounded-xl h-11"
                >
                  Retour
                </Button>
                <Button
                  onClick={handleVerifyEmail}
                  disabled={verifyEmailMutation.isPending || totpCode.length !== 6}
                  className="flex-1 bg-schooltrack-primary hover:bg-blue-900 text-white rounded-xl h-11"
                >
                  {verifyEmailMutation.isPending ? <Loader2 className="w-4 h-4 animate-spin mr-2" /> : null}
                  Verifier et activer
                </Button>
              </div>

              <button
                type="button"
                onClick={() => resendCodeMutation.mutate()}
                disabled={resendCodeMutation.isPending}
                className="w-full text-sm text-slate-500 hover:text-schooltrack-primary transition-colors"
              >
                {resendCodeMutation.isPending ? 'Envoi en cours...' : 'Renvoyer le code'}
              </button>
            </div>
          )}

          {/* === ENABLED : statut + desactiver === */}
          {is2FAEnabled && !isEnabling && twoFAStep !== 'done' && (
            <div className="flex items-center justify-between p-4 bg-green-50 border border-green-100 rounded-xl">
              <div className="flex items-center gap-3">
                <ShieldCheck className="w-5 h-5 text-green-600" />
                <span className="text-sm text-green-800 font-medium">Votre compte est protege par la 2FA.</span>
              </div>
              <Button
                variant="outline"
                size="sm"
                onClick={handleDisable2FA}
                disabled={disableMutation.isPending}
                className="text-red-600 border-red-200 hover:bg-red-50 rounded-lg"
              >
                {disableMutation.isPending ? <Loader2 className="w-4 h-4 animate-spin" /> : <ShieldOff className="w-4 h-4 mr-1" />}
                Desactiver
              </Button>
            </div>
          )}

          {/* === DONE : message succes apres activation === */}
          {twoFAStep === 'done' && is2FAEnabled && (
            <div className="flex items-center justify-between p-4 bg-green-50 border border-green-100 rounded-xl">
              <div className="flex items-center gap-3">
                <ShieldCheck className="w-5 h-5 text-green-600" />
                <span className="text-sm text-green-800 font-medium">Votre compte est protege par la 2FA.</span>
              </div>
              <Button
                variant="outline"
                size="sm"
                onClick={handleDisable2FA}
                disabled={disableMutation.isPending}
                className="text-red-600 border-red-200 hover:bg-red-50 rounded-lg"
              >
                {disableMutation.isPending ? <Loader2 className="w-4 h-4 animate-spin" /> : <ShieldOff className="w-4 h-4 mr-1" />}
                Desactiver
              </Button>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Section changement de mot de passe */}
      <Card className="border-slate-200 shadow-sm rounded-2xl">
        <CardHeader className="pb-4">
          <CardTitle className="text-lg font-heading text-schooltrack-primary flex items-center gap-2">
            <Lock className="w-5 h-5" />
            Changer le mot de passe
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {pwError && (
            <div className="p-3 bg-red-50 text-red-700 border border-red-100 rounded-xl text-sm flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0" />
              {pwError}
            </div>
          )}
          {pwSuccess && (
            <div className="p-3 bg-green-50 text-green-700 border border-green-100 rounded-xl text-sm flex items-center gap-2">
              <CheckCircle className="w-4 h-4 shrink-0" />
              {pwSuccess}
            </div>
          )}

          <div className="space-y-2">
            <Label htmlFor="current-pw" className="text-slate-700 font-medium">Mot de passe actuel</Label>
            <div className="relative">
              <Input
                id="current-pw"
                type={showCurrentPw ? 'text' : 'password'}
                value={currentPassword}
                onChange={(e) => setCurrentPassword(e.target.value)}
                className="h-11 pr-10 border-slate-200 rounded-xl"
              />
              <button
                type="button"
                onClick={() => setShowCurrentPw(!showCurrentPw)}
                className="absolute inset-y-0 right-0 flex items-center pr-3 text-slate-400 hover:text-slate-600"
              >
                {showCurrentPw ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
              </button>
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="new-pw" className="text-slate-700 font-medium">Nouveau mot de passe</Label>
            <div className="relative">
              <Input
                id="new-pw"
                type={showNewPw ? 'text' : 'password'}
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                className="h-11 pr-10 border-slate-200 rounded-xl"
              />
              <button
                type="button"
                onClick={() => setShowNewPw(!showNewPw)}
                className="absolute inset-y-0 right-0 flex items-center pr-3 text-slate-400 hover:text-slate-600"
              >
                {showNewPw ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
              </button>
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="confirm-pw" className="text-slate-700 font-medium">Confirmer le nouveau mot de passe</Label>
            <Input
              id="confirm-pw"
              type="password"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              className="h-11 border-slate-200 rounded-xl"
            />
          </div>

          <Button
            onClick={handleChangePassword}
            disabled={changePasswordMutation.isPending || !currentPassword || !newPassword || !confirmPassword}
            className="bg-schooltrack-primary hover:bg-blue-900 text-white rounded-xl h-11 px-6"
          >
            {changePasswordMutation.isPending ? <Loader2 className="w-4 h-4 animate-spin mr-2" /> : null}
            Modifier le mot de passe
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}
