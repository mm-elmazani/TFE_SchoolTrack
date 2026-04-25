import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { Link, useParams, useSearchParams } from 'react-router-dom';
import { apiClient } from '@/api/axios';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { GraduationCap, Lock, Eye, EyeOff, Loader2, AlertCircle, CheckCircle2, ArrowLeft } from 'lucide-react';
import { getApiError } from '@/lib/utils';

const resetSchema = z.object({
  new_password: z.string()
    .min(8, 'Le mot de passe doit contenir au moins 8 caracteres')
    .regex(/[A-Z]/, 'Au moins une majuscule')
    .regex(/\d/, 'Au moins un chiffre')
    .regex(/[^A-Za-z0-9]/, 'Au moins un caractere special'),
  confirm_password: z.string(),
}).refine((data) => data.new_password === data.confirm_password, {
  message: 'Les mots de passe ne correspondent pas',
  path: ['confirm_password'],
});

type ResetForm = z.infer<typeof resetSchema>;

export default function ResetPasswordScreen() {
  const { schoolSlug } = useParams();
  const [searchParams] = useSearchParams();
  const token = searchParams.get('token') || '';
  const email = searchParams.get('email') || '';

  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [showPassword, setShowPassword] = useState(false);

  const { register, handleSubmit, formState: { errors } } = useForm<ResetForm>({
    resolver: zodResolver(resetSchema),
  });

  const onSubmit = async (data: ResetForm) => {
    if (!token || !email) {
      setError('Lien de reinitialisation invalide. Parametres manquants.');
      return;
    }

    setIsLoading(true);
    setError(null);
    try {
      await apiClient.post('/api/v1/auth/reset-password', {
        token,
        email,
        new_password: data.new_password,
      });
      setSuccess(true);
    } catch (err: any) {
      setError(getApiError(err, 'Une erreur est survenue'));
    } finally {
      setIsLoading(false);
    }
  };

  if (!token || !email) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-schooltrack-neutral p-4">
        <Card className="w-full max-w-[420px] shadow-md border-slate-200 overflow-hidden rounded-2xl">
          <div className="h-1.5 bg-schooltrack-primary w-full" />
          <CardHeader className="space-y-1 pb-6 pt-8 items-center text-center">
            <GraduationCap className="h-12 w-12 text-schooltrack-primary mb-2" />
            <CardTitle className="text-2xl font-bold tracking-tight text-schooltrack-primary">Lien invalide</CardTitle>
          </CardHeader>
          <CardContent className="text-center space-y-6">
            <div className="p-4 bg-red-50 text-schooltrack-error border border-red-100 rounded-xl text-sm flex items-start gap-2">
              <AlertCircle className="h-5 w-5 shrink-0" />
              <span>Le lien de reinitialisation est invalide ou incomplet.</span>
            </div>
            <Link
              to={`/${schoolSlug}/forgot-password`}
              className="flex items-center justify-center gap-2 w-full text-sm text-schooltrack-primary hover:text-blue-900 transition-colors font-medium"
            >
              Demander un nouveau lien
            </Link>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-schooltrack-neutral p-4">
      <Card className="w-full max-w-[420px] shadow-md border-slate-200 overflow-hidden rounded-2xl">
        <div className="h-1.5 bg-schooltrack-primary w-full" />
        <CardHeader className="space-y-1 pb-6 pt-8 items-center text-center">
          <GraduationCap className="h-12 w-12 text-schooltrack-primary mb-2" />
          <CardTitle className="text-2xl font-bold tracking-tight text-schooltrack-primary">Nouveau mot de passe</CardTitle>
          <CardDescription className="text-slate-500 text-sm">
            Definissez un nouveau mot de passe pour votre compte.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {error && (
            <div className="mb-6 p-4 bg-red-50 text-schooltrack-error border border-red-100 rounded-xl text-sm flex items-start gap-2 animate-in fade-in zoom-in duration-200">
              <AlertCircle className="h-5 w-5 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          {success ? (
            <div className="space-y-6">
              <div className="p-4 bg-green-50 text-green-700 border border-green-100 rounded-xl text-sm flex items-start gap-2">
                <CheckCircle2 className="h-5 w-5 shrink-0 text-green-600" />
                <span>Votre mot de passe a ete reinitialise avec succes. Vous pouvez maintenant vous connecter.</span>
              </div>
              <Link
                to={`/${schoolSlug}/login`}
                className="flex items-center justify-center gap-2 w-full h-12 bg-schooltrack-primary hover:bg-blue-900 text-white font-semibold rounded-xl shadow-lg shadow-blue-900/20 transition-all active:scale-[0.98]"
              >
                Se connecter
              </Link>
            </div>
          ) : (
            <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
              <div className="space-y-2">
                <Label htmlFor="new_password" className="text-slate-700 font-medium ml-1">Nouveau mot de passe</Label>
                <div className="relative group">
                  <div className="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none text-slate-400 group-focus-within:text-schooltrack-primary transition-colors">
                    <Lock className="h-4 w-4" />
                  </div>
                  <Input
                    id="new_password"
                    type={showPassword ? 'text' : 'password'}
                    autoFocus
                    {...register('new_password')}
                    className={`pl-10 h-12 border-slate-200 rounded-xl transition-all focus:border-schooltrack-primary focus:ring-1 focus:ring-schooltrack-primary ${errors.new_password ? 'border-schooltrack-error bg-red-50/30' : ''}`}
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute inset-y-0 right-0 flex items-center pr-3 text-slate-400 hover:text-schooltrack-primary transition-colors"
                    aria-label={showPassword ? "Masquer" : "Afficher"}
                  >
                    {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </button>
                </div>
                {errors.new_password && <p className="text-schooltrack-error text-xs font-medium mt-1 ml-1">{errors.new_password.message}</p>}
                <p className="text-slate-400 text-xs ml-1">Min. 8 caracteres, 1 majuscule, 1 chiffre, 1 special</p>
              </div>

              <div className="space-y-2">
                <Label htmlFor="confirm_password" className="text-slate-700 font-medium ml-1">Confirmer le mot de passe</Label>
                <div className="relative group">
                  <div className="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none text-slate-400 group-focus-within:text-schooltrack-primary transition-colors">
                    <Lock className="h-4 w-4" />
                  </div>
                  <Input
                    id="confirm_password"
                    type={showPassword ? 'text' : 'password'}
                    {...register('confirm_password')}
                    className={`pl-10 h-12 border-slate-200 rounded-xl transition-all focus:border-schooltrack-primary focus:ring-1 focus:ring-schooltrack-primary ${errors.confirm_password ? 'border-schooltrack-error bg-red-50/30' : ''}`}
                  />
                </div>
                {errors.confirm_password && <p className="text-schooltrack-error text-xs font-medium mt-1 ml-1">{errors.confirm_password.message}</p>}
              </div>

              <Button
                type="submit"
                className="w-full h-12 bg-schooltrack-primary hover:bg-blue-900 text-white font-semibold rounded-xl shadow-lg shadow-blue-900/20 transition-all active:scale-[0.98] disabled:opacity-70"
                disabled={isLoading}
              >
                {isLoading ? (
                  <>
                    <Loader2 className="mr-2 h-5 w-5 animate-spin" />
                    Reinitialisation...
                  </>
                ) : 'Reinitialiser le mot de passe'}
              </Button>

              <Link
                to={`/${schoolSlug}/login`}
                className="flex items-center justify-center gap-2 w-full text-sm text-slate-500 hover:text-schooltrack-primary transition-colors"
              >
                <ArrowLeft className="h-4 w-4" />
                Retour a la connexion
              </Link>
            </form>
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
