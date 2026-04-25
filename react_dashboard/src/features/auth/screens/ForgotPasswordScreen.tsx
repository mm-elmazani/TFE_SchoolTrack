import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { Link, useParams } from 'react-router-dom';
import { apiClient } from '@/api/axios';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { GraduationCap, Mail, Loader2, AlertCircle, CheckCircle2, ArrowLeft } from 'lucide-react';

const forgotSchema = z.object({
  email: z.string().email('Email invalide'),
});

type ForgotForm = z.infer<typeof forgotSchema>;

export default function ForgotPasswordScreen() {
  const { schoolSlug } = useParams();
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  const { register, handleSubmit, formState: { errors } } = useForm<ForgotForm>({
    resolver: zodResolver(forgotSchema),
  });

  const onSubmit = async (data: ForgotForm) => {
    setIsLoading(true);
    setError(null);
    try {
      await apiClient.post('/api/v1/auth/forgot-password', { email: data.email, school_slug: schoolSlug });
      setSuccess(true);
    } catch (err: any) {
      const detail = err.response?.data?.detail || 'Une erreur est survenue. Veuillez reessayer.';
      setError(detail);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-schooltrack-neutral p-4">
      <Card className="w-full max-w-[420px] shadow-md border-slate-200 overflow-hidden rounded-2xl">
        <div className="h-1.5 bg-schooltrack-primary w-full" />
        <CardHeader className="space-y-1 pb-6 pt-8 items-center text-center">
          <GraduationCap className="h-12 w-12 text-schooltrack-primary mb-2" />
          <CardTitle className="text-2xl font-bold tracking-tight text-schooltrack-primary">Mot de passe oublie</CardTitle>
          <CardDescription className="text-slate-500 text-sm">
            Entrez votre adresse email pour recevoir un lien de reinitialisation.
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
                <span>Si un compte existe avec cet email, un lien de reinitialisation a ete envoye. Verifiez votre boite de reception.</span>
              </div>
              <Link
                to={`/${schoolSlug}/login`}
                className="flex items-center justify-center gap-2 w-full text-sm text-slate-500 hover:text-schooltrack-primary transition-colors"
              >
                <ArrowLeft className="h-4 w-4" />
                Retour a la connexion
              </Link>
            </div>
          ) : (
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
                    autoFocus
                    {...register('email')}
                    className={`pl-10 h-12 border-slate-200 rounded-xl transition-all focus:border-schooltrack-primary focus:ring-1 focus:ring-schooltrack-primary ${errors.email ? 'border-schooltrack-error bg-red-50/30' : ''}`}
                  />
                </div>
                {errors.email && <p className="text-schooltrack-error text-xs font-medium mt-1 ml-1">{errors.email.message}</p>}
              </div>

              <Button
                type="submit"
                className="w-full h-12 bg-schooltrack-primary hover:bg-blue-900 text-white font-semibold rounded-xl shadow-lg shadow-blue-900/20 transition-all active:scale-[0.98] disabled:opacity-70"
                disabled={isLoading}
              >
                {isLoading ? (
                  <>
                    <Loader2 className="mr-2 h-5 w-5 animate-spin" />
                    Envoi en cours...
                  </>
                ) : 'Envoyer le lien'}
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
