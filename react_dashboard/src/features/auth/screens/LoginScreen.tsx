import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useNavigate } from 'react-router-dom';
import { useAuthStore } from '../store/authStore';
import { apiClient } from '@/api/axios';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Eye, EyeOff, Loader2, Lock, Mail, AlertCircle, ShieldCheck } from 'lucide-react';

const loginSchema = z.object({
  email: z.string().email('Email invalide'),
  password: z.string().min(1, 'Mot de passe requis'),
});

type LoginForm = z.infer<typeof loginSchema>;

export default function LoginScreen() {
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [needs2FA, setNeeds2FA] = useState(false);
  const [totpCode, setTotpCode] = useState('');
  const navigate = useNavigate();
  const setAuth = useAuthStore((state) => state.setAuth);

  const { register, handleSubmit, formState: { errors }, getValues } = useForm<LoginForm>({
    resolver: zodResolver(loginSchema),
  });

  const doLogin = async (email: string, password: string, totp_code?: string) => {
    setIsLoading(true);
    setError(null);
    try {
      const payload: Record<string, string> = { email, password };
      if (totp_code) payload.totp_code = totp_code;

      const response = await apiClient.post('/api/v1/auth/login', payload);
      const { access_token, refresh_token, user } = response.data;
      setAuth(access_token, refresh_token, user);
      navigate('/students', { replace: true });
    } catch (err: any) {
      const detail = err.response?.data?.detail || '';
      if (detail === '2FA_REQUIRED') {
        setNeeds2FA(true);
        setError(null);
      } else {
        setError(detail || 'Une erreur est survenue lors de la connexion');
      }
    } finally {
      setIsLoading(false);
    }
  };

  const onSubmit = async (data: LoginForm) => {
    await doLogin(data.email, data.password);
  };

  const onSubmit2FA = async () => {
    if (totpCode.length !== 6) {
      setError('Le code 2FA doit contenir 6 chiffres');
      return;
    }
    const { email, password } = getValues();
    await doLogin(email, password, totpCode);
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-schooltrack-neutral p-4">
      <Card className="w-full max-w-md shadow-2xl border-slate-200 overflow-hidden rounded-2xl">
        <div className="h-2 bg-schooltrack-primary w-full" />
        <CardHeader className="space-y-2 pb-6 pt-8">
          <CardTitle className="text-3xl font-bold tracking-tight text-schooltrack-primary">SchoolTrack</CardTitle>
          <CardDescription className="text-slate-500 text-base">
            {needs2FA
              ? 'Entrez le code de votre application d\'authentification.'
              : 'Gérez vos élèves et voyages scolaires en toute sécurité.'}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {error && (
            <div className="mb-6 p-4 bg-red-50 text-schooltrack-error border border-red-100 rounded-xl text-sm flex items-start gap-2 animate-in fade-in zoom-in duration-200">
              <AlertCircle className="h-5 w-5 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          {!needs2FA ? (
            <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
              <div className="space-y-2">
                <Label htmlFor="email" className="text-slate-700 font-medium ml-1">Adresse Email</Label>
                <div className="relative group">
                  <div className="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none text-slate-400 group-focus-within:text-schooltrack-primary transition-colors">
                    <Mail className="h-4 w-4" />
                  </div>
                  <Input
                    id="email"
                    type="email"
                    placeholder="nom@ecole.be"
                    autoComplete="email"
                    {...register('email')}
                    className={`pl-10 h-12 border-slate-200 rounded-xl transition-all focus:border-schooltrack-primary focus:ring-1 focus:ring-schooltrack-primary ${errors.email ? 'border-schooltrack-error bg-red-50/30' : ''}`}
                  />
                </div>
                {errors.email && <p className="text-schooltrack-error text-xs font-medium mt-1 ml-1">{errors.email.message}</p>}
              </div>

              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <Label htmlFor="password" title="password" className="text-slate-700 font-medium ml-1">Mot de passe</Label>
                </div>
                <div className="relative group">
                  <div className="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none text-slate-400 group-focus-within:text-schooltrack-primary transition-colors">
                    <Lock className="h-4 w-4" />
                  </div>
                  <Input
                    id="password"
                    type={showPassword ? 'text' : 'password'}
                    autoComplete="current-password"
                    {...register('password')}
                    className={`pl-10 h-12 border-slate-200 rounded-xl transition-all focus:border-schooltrack-primary focus:ring-1 focus:ring-schooltrack-primary ${errors.password ? 'border-schooltrack-error bg-red-50/30' : ''}`}
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute inset-y-0 right-0 flex items-center pr-3 text-slate-400 hover:text-schooltrack-primary transition-colors"
                    aria-label={showPassword ? "Masquer le mot de passe" : "Afficher le mot de passe"}
                  >
                    {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </button>
                </div>
                {errors.password && <p className="text-schooltrack-error text-xs font-medium mt-1 ml-1">{errors.password.message}</p>}
              </div>

              <Button
                type="submit"
                className="w-full h-12 bg-schooltrack-primary hover:bg-blue-900 text-white font-semibold rounded-xl shadow-lg shadow-blue-900/20 transition-all active:scale-[0.98] disabled:opacity-70"
                disabled={isLoading}
              >
                {isLoading ? (
                  <>
                    <Loader2 className="mr-2 h-5 w-5 animate-spin" />
                    Connexion en cours...
                  </>
                ) : 'Se connecter'}
              </Button>
            </form>
          ) : (
            <div className="space-y-6">
              <div className="space-y-2">
                <Label htmlFor="totp" className="text-slate-700 font-medium ml-1">Code 2FA (6 chiffres)</Label>
                <div className="relative group">
                  <div className="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none text-slate-400 group-focus-within:text-schooltrack-primary transition-colors">
                    <ShieldCheck className="h-4 w-4" />
                  </div>
                  <Input
                    id="totp"
                    type="text"
                    inputMode="numeric"
                    maxLength={6}
                    placeholder="000000"
                    autoFocus
                    value={totpCode}
                    onChange={(e) => setTotpCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
                    className="pl-10 h-12 border-slate-200 rounded-xl transition-all focus:border-schooltrack-primary focus:ring-1 focus:ring-schooltrack-primary text-center text-2xl tracking-[0.5em] font-mono"
                  />
                </div>
              </div>

              <Button
                onClick={onSubmit2FA}
                className="w-full h-12 bg-schooltrack-primary hover:bg-blue-900 text-white font-semibold rounded-xl shadow-lg shadow-blue-900/20 transition-all active:scale-[0.98] disabled:opacity-70"
                disabled={isLoading || totpCode.length !== 6}
              >
                {isLoading ? (
                  <>
                    <Loader2 className="mr-2 h-5 w-5 animate-spin" />
                    Vérification...
                  </>
                ) : 'Vérifier'}
              </Button>

              <button
                type="button"
                onClick={() => { setNeeds2FA(false); setTotpCode(''); setError(null); }}
                className="w-full text-sm text-slate-500 hover:text-schooltrack-primary transition-colors"
              >
                Retour a la connexion
              </button>
            </div>
          )}

          <div className="mt-10 pt-6 border-t border-slate-100 text-center">
            <p className="text-[10px] text-slate-400 uppercase tracking-widest font-medium">
              SchoolTrack &copy; 2026 - EPHEC
            </p>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
